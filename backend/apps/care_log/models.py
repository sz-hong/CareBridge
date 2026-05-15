import uuid

from django.conf import settings
from django.db import models


class CareLog(models.Model):
    class Type(models.TextChoices):
        MEDICATION = 'medication', 'Medication'
        VITAL = 'vital', 'Vital'
        MEAL = 'meal', 'Meal'
        ACTIVITY = 'activity', 'Activity'
        NOTE = 'note', 'Note'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='care_logs'
    )
    recorder = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='care_logs',
    )
    type = models.CharField(max_length=20, choices=Type.choices)
    content = models.JSONField()
    content_translated = models.JSONField(null=True, blank=True)
    photo_url = models.URLField(max_length=500, null=True, blank=True)
    timestamp = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'care_log'
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['family', '-timestamp'], name='idx_carelog_family_time'),
            models.Index(fields=['family', 'type'], name='idx_carelog_family_type'),
        ]

    def __str__(self):
        return f'{self.type} log by {self.recorder} at {self.timestamp}'
