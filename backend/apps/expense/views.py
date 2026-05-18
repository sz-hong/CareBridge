import uuid

from django.db.models import Sum, Count
from django.db.models.functions import TruncMonth
from django.utils import timezone
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.permissions import CaregiverCannotDelete
from core.responses import empty_success_response, success_response
from core.upload_paths import (
    build_quarantine_key,
    is_valid_quarantine_key,
    processed_key_for_raw_key,
)
from core.viewsets import FamilyScopedQuerySetMixin
from .categories import normalize_expense_category
from .models import Expense
from .serializers import (
    CreateExpenseSerializer,
    ExpenseSerializer,
    ScanReceiptSerializer,
)
from .tasks import redact_receipt_image_task


class ExpenseViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]
    serializer_class = ExpenseSerializer
    filterset_fields = ['status']

    def get_queryset(self):
        qs = self.scope_queryset_to_family(Expense.objects.all())

        date_from = self.request.query_params.get('date_from')
        date_to = self.request.query_params.get('date_to')
        if date_from:
            qs = qs.filter(date__gte=date_from)
        if date_to:
            qs = qs.filter(date__lte=date_to)

        return qs

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateExpenseSerializer
        return ExpenseSerializer

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(
                data=paginated.data['results'],
                meta={
                    'count': paginated.data['count'],
                    'next': paginated.data.get('next'),
                    'previous': paginated.data.get('previous'),
                },
            )
        serializer = self.get_serializer(queryset, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateExpenseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_image_key = serializer.validated_data.get('raw_image_key')
        if raw_image_key:
            self._validate_receipt_key(raw_image_key, request.user.family.id)

        expense = serializer.save(
            family=request.user.family,
            recorder=request.user,
        )
        if raw_image_key:
            expense.image_url = None
            expense.raw_image_key = raw_image_key
            expense.redacted_image_key = processed_key_for_raw_key(raw_image_key)
            expense.deid_status = Expense.DeidentificationStatus.PROCESSING
            expense.save(update_fields=[
                'image_url',
                'raw_image_key',
                'redacted_image_key',
                'deid_status',
                'updated_at',
            ])
            redact_receipt_image_task.delay(expense.id)

        out = ExpenseSerializer(expense).data
        return success_response(data=out, status=201)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        return success_response(data=serializer.data)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = CreateExpenseSerializer(
            instance, data=request.data, partial=partial,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        out = ExpenseSerializer(instance).data
        return success_response(data=out)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return empty_success_response()

    @action(detail=False, methods=['post'], url_path='upload-url')
    def upload_url(self, request):
        """Return a presigned PUT URL for a quarantine receipt object."""
        from core.storage import generate_upload_url

        content_type = request.data.get('content_type') or 'image/jpeg'
        family_id = getattr(request.user.family, 'id', None)
        key = build_quarantine_key(family_id, 'receipts', content_type)

        put_url = generate_upload_url(key, content_type)
        return success_response(data={
            'upload_id': key.rsplit('/', 1)[-1].split('.', 1)[0],
            'upload_url': put_url,
            'raw_key': key,
            'expires_in': 3600,
        })

    @action(detail=False, methods=['post'], url_path='scan')
    def scan(self, request):
        """Create a processing expense from a legacy image URL or quarantine key."""
        serializer = ScanReceiptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_key = serializer.validated_data.get('raw_key')

        create_kwargs = {
            'family': request.user.family,
            'recorder': request.user,
            'scan_id': serializer.validated_data.get('upload_id') or str(uuid.uuid4()),
            'date': request.data.get('date', None) or timezone.now().date(),
            'items': [],
            'total_amount': 0,
            'status': Expense.Status.PROCESSING,
        }

        if raw_key:
            self._validate_receipt_key(raw_key, request.user.family.id)
            create_kwargs.update({
                'image_url': None,
                'raw_image_key': raw_key,
                'redacted_image_key': processed_key_for_raw_key(raw_key),
                'deid_status': Expense.DeidentificationStatus.PROCESSING,
            })
        else:
            create_kwargs['image_url'] = serializer.validated_data['image_url']

        expense = Expense.objects.create(**create_kwargs)
        if raw_key:
            redact_receipt_image_task.delay(expense.id)
        out = ExpenseSerializer(expense).data
        return success_response(data=out, status=202)

    @action(detail=False, methods=['get'], url_path='monthly')
    def monthly(self, request):
        """Return current-month total and category breakdown."""
        family = request.user.family
        today = timezone.localdate()
        month_start = today.replace(day=1)

        qs = Expense.objects.filter(
            family=family,
            status=Expense.Status.COMPLETED,
            date__gte=month_start,
            date__lte=today,
        )

        monthly_total = 0.0
        category_totals = {}
        for expense in qs:
            monthly_total += float(expense.total_amount or 0)
            for item in (expense.items or []):
                cat = normalize_expense_category(item.get('category'))
                amount = float(item.get('total') or 0)
                category_totals[cat] = category_totals.get(cat, 0.0) + amount

        total_for_pct = sum(category_totals.values()) or 1.0
        category_breakdown = [
            {
                'category': cat,
                'percentage': round(amount / total_for_pct * 100, 1),
            }
            for cat, amount in sorted(
                category_totals.items(), key=lambda x: -x[1]
            )
        ]

        return success_response(data={
            'monthly_total': round(monthly_total, 2),
            'category_breakdown': category_breakdown,
        })

    def _validate_receipt_key(self, raw_key, family_id):
        if not is_valid_quarantine_key(raw_key, family_id, 'receipts'):
            raise ValidationError({
                'raw_key': 'Receipt upload key is outside this family quarantine path.'
            })
