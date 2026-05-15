from django.utils import timezone
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.permissions import CaregiverCannotDelete, CaregiverMedicationPermission
from core.responses import empty_success_response, success_response
from core.viewsets import FamilyScopedQuerySetMixin
from core.translation import translate_content_fields, translate_for_user
from apps.care_log.models import CareLog
from .models import Medication, MedicationConfirmation
from .serializers import (
    MedicationSerializer,
    CreateMedicationSerializer,
    MedicationConfirmationSerializer,
    ConfirmMedicationSerializer,
)

class MedicationViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [
        IsAuthenticated,
        CaregiverCannotDelete,
        CaregiverMedicationPermission,
    ]
    serializer_class = MedicationSerializer

    def get_queryset(self):
        from django.db.models import Q

        qs = self.scope_queryset_to_family(Medication.objects.all())
        is_active = self.request.query_params.get('is_active')
        if is_active is not None:
            qs = qs.filter(is_active=is_active.lower() == 'true')

        # Hide medications whose treatment course has ended. The FE already
        # filters these out, but doing it here keeps API responses honest and
        # spares clients from filtering expired records.
        # Pass ?include_expired=true to override (e.g. an admin/history view).
        if self.request.query_params.get('include_expired', '').lower() != 'true':
            today = timezone.localdate()
            qs = qs.filter(Q(end_date__isnull=True) | Q(end_date__gte=today))

        return qs

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateMedicationSerializer
        return MedicationSerializer

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
        serializer = CreateMedicationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        medication = serializer.save(
            family=request.user.family,
            created_by=request.user,
        )

        medication.name_translated = translate_for_user(
            medication.name, user=request.user,
        )
        medication.instructions_translated = translate_for_user(
            medication.instructions or '', user=request.user,
        )
        medication.save(update_fields=[
            'name_translated', 'instructions_translated',
        ])

        out = MedicationSerializer(medication).data
        return success_response(data=out, status=201)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = MedicationSerializer(instance)
        return success_response(data=serializer.data)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = CreateMedicationSerializer(
            instance, data=request.data, partial=partial,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        if 'name' in request.data:
            instance.name_translated = translate_for_user(
                instance.name, user=request.user,
            )
        if 'instructions' in request.data:
            instance.instructions_translated = translate_for_user(
                instance.instructions or '', user=request.user,
            )
        instance.save(update_fields=[
            'name_translated', 'instructions_translated', 'updated_at',
        ])
        out = MedicationSerializer(instance).data
        return success_response(data=out)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return empty_success_response()

    @action(detail=True, methods=['post'], url_path='confirm')
    def confirm(self, request, pk=None):
        medication = self.get_object()
        serializer = ConfirmMedicationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        note = serializer.validated_data.get('note', '')
        note_translated = translate_for_user(note, user=request.user)

        # Create a CareLog entry for medication confirmation
        care_log_content = {
            'medication_id': str(medication.id),
            'medication_name': medication.name,
            'dosage': medication.dosage,
            'scheduled_time': serializer.validated_data['scheduled_time'],
            'note': note,
        }
        care_log = CareLog.objects.create(
            family=medication.family,
            recorder=request.user,
            type=CareLog.Type.MEDICATION,
            content=care_log_content,
            content_translated=translate_content_fields(
                care_log_content,
                user=request.user,
                keys={'medication_name', 'note'},
            ),
            photo_url=serializer.validated_data.get('photo_url'),
            timestamp=timezone.now(),
        )

        # Create confirmation record linked to care_log
        confirmation = MedicationConfirmation.objects.create(
            medication=medication,
            confirmed_by=request.user,
            photo_url=serializer.validated_data.get('photo_url'),
            scheduled_time=serializer.validated_data['scheduled_time'],
            note=note,
            note_translated=note_translated,
            care_log=care_log,
        )

        out = MedicationConfirmationSerializer(confirmation).data
        return success_response(data=out, status=201)

    @action(detail=False, methods=['get'], url_path='today_confirmations')
    def today_confirmations(self, request):
        today = timezone.localdate()
        confirmations = MedicationConfirmation.objects.filter(
            medication__family=request.user.family,
            confirmed_at__date=today
        ).select_related('medication')
        
        out = MedicationConfirmationSerializer(confirmations, many=True).data
        return success_response(data=out)
