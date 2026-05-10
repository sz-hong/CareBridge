import uuid

from django.conf import settings
from django.db import models


class HealthData(models.Model):
    class Type(models.TextChoices):
        HEART_RATE = 'heart_rate', 'Heart Rate'
        BLOOD_OXYGEN = 'blood_oxygen', 'Blood Oxygen'
        STEP_COUNT = 'step_count', 'Step Count'
        ACTIVE_ENERGY = 'active_energy', 'Active Energy'
        BLOOD_PRESSURE_SYSTOLIC = 'blood_pressure_systolic', 'Blood Pressure Systolic'
        BLOOD_PRESSURE_DIASTOLIC = 'blood_pressure_diastolic', 'Blood Pressure Diastolic'

    class Unit(models.TextChoices):
        BPM = 'bpm', 'BPM'
        PERCENT = '%', '%'
        STEPS = 'steps', 'Steps'
        KCAL = 'kcal', 'kcal'
        MMHG = 'mmHg', 'mmHg'

    class Source(models.TextChoices):
        APPLE_WATCH = 'apple_watch', 'Apple Watch'
        IPHONE      = 'iphone',      'iPhone'
        MANUAL      = 'manual',      'Manual'
        OTHER       = 'other',       'Other'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='health_data'
    )
    device_id = models.CharField(max_length=100, null=True, blank=True)
    source = models.CharField(
        max_length=16, choices=Source.choices, default=Source.OTHER,
    )
    type = models.CharField(max_length=32, choices=Type.choices)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=10, choices=Unit.choices)
    recorded_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'health_data'
        unique_together = ('family', 'type', 'recorded_at')
        ordering = ['-recorded_at']
        indexes = [
            models.Index(fields=['family', 'type', '-recorded_at'], name='idx_health_query'),
        ]

    def __str__(self):
        return f'{self.type}: {self.value} {self.unit} at {self.recorded_at}'


class HealthAlertThreshold(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.OneToOneField(
        'family.Family', on_delete=models.CASCADE, related_name='health_alert_threshold'
    )
    heart_rate_high = models.IntegerField(default=100)
    heart_rate_low = models.IntegerField(default=50)
    blood_oxygen_low = models.DecimalField(
        max_digits=4, decimal_places=1, default=93.0
    )
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='updated_thresholds',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'health_alert_threshold'

    def __str__(self):
        return f'Thresholds for {self.family}'


class HealthAlert(models.Model):
    class Severity(models.TextChoices):
        WARNING = 'warning', 'Warning'
        CRITICAL = 'critical', 'Critical'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='health_alerts'
    )
    type = models.CharField(max_length=32)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    threshold = models.DecimalField(max_digits=10, decimal_places=2)
    severity = models.CharField(max_length=10, choices=Severity.choices)
    acknowledged_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='acknowledged_alerts',
    )
    acknowledged_at = models.DateTimeField(null=True, blank=True)
    recorded_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'health_alert'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['family', '-recorded_at'], name='idx_alert_family_time'),
        ]

    def __str__(self):
        return f'{self.severity} alert: {self.type} = {self.value} (threshold: {self.threshold})'
