import uuid

from django.conf import settings
from django.db import models


class Medication(models.Model):
    class Frequency(models.TextChoices):
        DAILY = 'daily', 'Daily'
        TWICE_DAILY = 'twice_daily', 'Twice Daily'
        THRICE_DAILY = 'thrice_daily', 'Thrice Daily'
        WEEKLY = 'weekly', 'Weekly'
        AS_NEEDED = 'as_needed', 'As Needed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='medications'
    )
    name = models.CharField(max_length=200)
    name_translated = models.JSONField(null=True, blank=True)
    dosage = models.CharField(max_length=50)
    frequency = models.CharField(max_length=20, choices=Frequency.choices)
    times = models.JSONField()
    instructions = models.TextField(null=True, blank=True)
    instructions_translated = models.JSONField(null=True, blank=True)
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    reminder_enabled = models.BooleanField(default=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='created_medications',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'medication'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['family', 'is_active'], name='idx_med_family_active'),
        ]

    def __str__(self):
        return f'{self.name} ({self.dosage})'


class MedicationConfirmation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    medication = models.ForeignKey(
        Medication, on_delete=models.CASCADE, related_name='confirmations'
    )
    confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='medication_confirmations',
    )
    photo_url = models.URLField(max_length=500, null=True, blank=True)
    scheduled_time = models.CharField(max_length=5)
    note = models.TextField(null=True, blank=True)
    care_log = models.ForeignKey(
        'care_log.CareLog',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='medication_confirmations',
    )
    confirmed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'medication_confirmation'
        ordering = ['-confirmed_at']

    def __str__(self):
        return f'{self.medication.name} confirmed by {self.confirmed_by} at {self.confirmed_at}'
