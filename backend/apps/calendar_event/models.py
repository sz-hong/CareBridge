import uuid

from django.conf import settings
from django.db import models


class Event(models.Model):
    class Type(models.TextChoices):
        MEDICAL = 'medical', 'Medical'
        MEDICATION = 'medication', 'Medication'
        REHAB = 'rehab', 'Rehab'
        LEAVE = 'leave', 'Leave'
        PERSONAL = 'personal', 'Personal'
        OTHER = 'other', 'Other'

    class Source(models.TextChoices):
        MANUAL = 'manual', 'Manual'
        MEDICATION = 'medication', 'Medication'
        LEAVE = 'leave', 'Leave'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='events'
    )
    title = models.CharField(max_length=200)
    title_translated = models.JSONField(null=True, blank=True)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField(null=True, blank=True)
    location = models.CharField(max_length=300, null=True, blank=True)
    type = models.CharField(max_length=20, choices=Type.choices)
    reminder_minutes = models.IntegerField(default=60)
    note = models.TextField(null=True, blank=True)
    source = models.CharField(
        max_length=20, choices=Source.choices, default=Source.MANUAL
    )
    source_id = models.UUIDField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='created_events',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'event'
        ordering = ['start_time']
        indexes = [
            models.Index(fields=['family', 'start_time'], name='idx_event_family_time'),
        ]

    def __str__(self):
        return f'{self.title} ({self.start_time})'
