from rest_framework import serializers

from .models import HealthData, HealthAlert, HealthAlertThreshold


class HealthDataSerializer(serializers.ModelSerializer):
    value = serializers.FloatField()

    class Meta:
        model = HealthData
        fields = [
            'id', 'family', 'device_id', 'type', 'value',
            'unit', 'recorded_at', 'created_at',
        ]
        read_only_fields = fields


class SyncHealthDataItemSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=HealthData.Type.choices)
    value = serializers.DecimalField(max_digits=10, decimal_places=2)
    unit = serializers.ChoiceField(choices=HealthData.Unit.choices)
    recorded_at = serializers.DateTimeField()
    device_id = serializers.CharField(max_length=100, required=False, default='')


class SyncHealthDataSerializer(serializers.Serializer):
    data = SyncHealthDataItemSerializer(many=True)


class HealthAlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = HealthAlert
        fields = [
            'id', 'family', 'type', 'value', 'threshold',
            'severity', 'acknowledged_by', 'acknowledged_at',
            'recorded_at', 'created_at',
        ]
        read_only_fields = fields


class HealthAlertThresholdSerializer(serializers.ModelSerializer):
    class Meta:
        model = HealthAlertThreshold
        fields = [
            'id', 'family', 'heart_rate_high', 'heart_rate_low',
            'blood_oxygen_low', 'updated_by', 'updated_at',
        ]
        read_only_fields = ['id', 'family', 'updated_by', 'updated_at']
