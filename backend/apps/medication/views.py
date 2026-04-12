import logging

from django.utils import timezone
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response
from core.translation import translate_text, SUPPORTED_LANGUAGES
from apps.care_log.models import CareLog
from .models import Medication, MedicationConfirmation
from .serializers import (
    MedicationSerializer,
    CreateMedicationSerializer,
    MedicationConfirmationSerializer,
    ConfirmMedicationSerializer,
)

logger = logging.getLogger(__name__)


class MedicationViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = MedicationSerializer

    def get_queryset(self):
        qs = Medication.objects.filter(family=self.request.user.family)
        is_active = self.request.query_params.get('is_active')
        if is_active is not None:
            qs = qs.filter(is_active=is_active.lower() == 'true')
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

        # Attempt auto-translation of name
        try:
            source_lang = request.user.language or 'zh-TW'
            target_langs = [
                code for code in SUPPORTED_LANGUAGES
                if code != source_lang
            ]
            if target_langs and medication.name:
                name_translated = translate_text(
                    medication.name, source_lang, target_langs,
                )
                medication.name_translated = name_translated
                if medication.instructions:
                    instructions_translated = translate_text(
                        medication.instructions, source_lang, target_langs,
                    )
                    medication.instructions_translated = instructions_translated
                medication.save(update_fields=[
                    'name_translated', 'instructions_translated',
                ])
        except Exception:
            logger.warning(
                'Auto-translation failed for medication %s', medication.id,
                exc_info=True,
            )

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
        out = MedicationSerializer(instance).data
        return success_response(data=out)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(status=204)

    @action(detail=True, methods=['post'], url_path='confirm')
    def confirm(self, request, pk=None):
        medication = self.get_object()
        serializer = ConfirmMedicationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Create a CareLog entry for medication confirmation
        care_log = CareLog.objects.create(
            family=medication.family,
            recorder=request.user,
            type=CareLog.Type.MEDICATION,
            content={
                'medication_id': str(medication.id),
                'medication_name': medication.name,
                'dosage': medication.dosage,
                'scheduled_time': serializer.validated_data['scheduled_time'],
                'note': serializer.validated_data.get('note', ''),
            },
            photo_url=serializer.validated_data.get('photo_url'),
            timestamp=timezone.now(),
        )

        # Create confirmation record linked to care_log
        confirmation = MedicationConfirmation.objects.create(
            medication=medication,
            confirmed_by=request.user,
            photo_url=serializer.validated_data['photo_url'],
            scheduled_time=serializer.validated_data['scheduled_time'],
            note=serializer.validated_data.get('note', ''),
            care_log=care_log,
        )

        out = MedicationConfirmationSerializer(confirmation).data
        return success_response(data=out, status=201)
