from rest_framework import serializers

from .models import HealthData, HealthAlert, HealthAlertThreshold


class HealthDataSerializer(serializers.ModelSerializer):
    value = serializers.FloatField()

    class Meta:
        model = HealthData
        fields = [
            'id', 'family', 'device_id', 'source', 'type', 'value',
            'unit', 'recorded_at', 'created_at',
        ]
        read_only_fields = fields


class SyncHealthDataItemSerializer(serializers.Serializer):
    """Wire format from clients (Apple Watch / HealthKit).

    `value` is intentionally a FloatField (not DecimalField) so noisy
    HealthKit input like SpO2 0.97833333… can be accepted; we round to 2
    decimal places ourselves before storing into the DecimalField column,
    so clients don't have to be precise.
    """
    type = serializers.ChoiceField(choices=HealthData.Type.choices)
    value = serializers.FloatField()
    unit = serializers.ChoiceField(choices=HealthData.Unit.choices)
    recorded_at = serializers.DateTimeField()
    device_id = serializers.CharField(max_length=100, required=False, default='')
    source = serializers.ChoiceField(
        choices=HealthData.Source.choices,
        required=False, default=HealthData.Source.OTHER,
    )

    def validate_type(self, value):
        if value in {
            HealthData.Type.BLOOD_PRESSURE_SYSTOLIC,
            HealthData.Type.BLOOD_PRESSURE_DIASTOLIC,
        }:
            raise serializers.ValidationError(
                'Blood pressure must be recorded manually in care logs.'
            )
        return value

    def validate_value(self, value):
        from decimal import Decimal, ROUND_HALF_UP
        # Coerce any precision to 2 dp matching the DecimalField(max_digits=10,
        # decimal_places=2) column. Reject only if the integer part is too big.
        quantized = Decimal(str(value)).quantize(
            Decimal('0.01'), rounding=ROUND_HALF_UP,
        )
        if quantized.adjusted() >= 8:  # > 99,999,999.99
            raise serializers.ValidationError('Value out of range.')
        return quantized


class SyncHealthDataSerializer(serializers.Serializer):
    data = SyncHealthDataItemSerializer(many=True)


class HealthAlertSerializer(serializers.ModelSerializer):
    # Emit floats (not DRF's default decimal-as-string) so the iOS client can
    # decode value/threshold straight into Double, matching HealthDataSerializer.
    value = serializers.FloatField()
    threshold = serializers.FloatField()

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
