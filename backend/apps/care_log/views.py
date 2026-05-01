from datetime import timedelta

from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response
from core.viewsets import FamilyScopedQuerySetMixin
from .models import CareLog
from .serializers import CareLogSerializer, CreateCareLogSerializer


class CareLogViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = CareLogSerializer
    filterset_fields = ['type']

    def get_queryset(self):
        qs = self.scope_queryset_to_family(CareLog.objects.all()).select_related('recorder')

        date_from = self.request.query_params.get('date_from')
        date_to = self.request.query_params.get('date_to')
        if date_from:
            qs = qs.filter(timestamp__date__gte=date_from)
        if date_to:
            qs = qs.filter(timestamp__date__lte=date_to)

        return qs

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateCareLogSerializer
        return CareLogSerializer

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
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(
            family=request.user.family,
            recorder=request.user,
        )
        out = CareLogSerializer(serializer.instance).data
        return success_response(data=out, status=201)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = CareLogSerializer(instance)
        return success_response(data=serializer.data)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = CreateCareLogSerializer(
            instance, data=request.data, partial=partial,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        out = CareLogSerializer(instance).data
        return success_response(data=out)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(status=204)

    @action(detail=False, methods=['get'], url_path='summary')
    def summary(self, request):
        family = request.user.family
        seven_days_ago = timezone.now() - timedelta(days=7)

        logs_qs = CareLog.objects.filter(
            family=family,
            timestamp__gte=seven_days_ago,
        )

        # Count by type
        total_logs = (
            logs_qs.values('type')
            .annotate(count=Count('id'))
            .order_by('type')
        )
        by_type = {item['type']: item['count'] for item in total_logs}

        # Medication compliance
        med_logs = logs_qs.filter(type=CareLog.Type.MEDICATION)
        med_total = med_logs.count()
        med_confirmed = med_logs.filter(
            medication_confirmations__isnull=False,
        ).distinct().count()

        data = {
            'period': {
                'from': seven_days_ago.isoformat(),
                'to': timezone.now().isoformat(),
            },
            'total_logs_by_type': by_type,
            'medication_compliance': {
                'confirmed': med_confirmed,
                'total': med_total,
                'rate': round(med_confirmed / med_total, 2) if med_total else 0,
            },
        }
        return success_response(data=data)
