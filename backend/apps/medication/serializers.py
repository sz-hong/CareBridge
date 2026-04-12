from rest_framework import serializers

from .models import Medication, MedicationConfirmation


class ConfirmedByMiniSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()


class MedicationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Medication
        fields = [
            'id', 'family', 'name', 'name_translated', 'dosage',
            'frequency', 'times', 'instructions', 'instructions_translated',
            'start_date', 'end_date', 'is_active', 'reminder_enabled',
            'created_by', 'created_at', 'updated_at',
        ]
        read_only_fields = fields


class CreateMedicationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Medication
        fields = [
            'name', 'dosage', 'frequency', 'times', 'instructions',
            'start_date', 'end_date', 'reminder_enabled',
        ]


class MedicationConfirmationSerializer(serializers.ModelSerializer):
    confirmed_by = ConfirmedByMiniSerializer(read_only=True)

    class Meta:
        model = MedicationConfirmation
        fields = [
            'id', 'medication', 'confirmed_by', 'photo_url',
            'scheduled_time', 'note', 'confirmed_at',
        ]
        read_only_fields = fields


class ConfirmMedicationSerializer(serializers.Serializer):
    photo_url = serializers.URLField(max_length=500)
    scheduled_time = serializers.CharField(max_length=5)
    note = serializers.CharField(required=False, allow_blank=True, default='')
