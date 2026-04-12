import uuid

from django.conf import settings
from django.db import models


class SOSRecord(models.Model):
    class Status(models.TextChoices):
        TRIGGERED = 'triggered', 'Triggered'
        RESOLVED = 'resolved', 'Resolved'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='sos_records'
    )
    triggered_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='sos_records',
    )
    location = models.JSONField(null=True, blank=True)
    situation = models.TextField(null=True, blank=True)
    auto_call_119 = models.BooleanField(default=True)
    notified_members = models.JSONField(null=True, blank=True)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.TRIGGERED
    )
    triggered_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'sos_record'
        ordering = ['-triggered_at']

    def __str__(self):
        return f'SOS by {self.triggered_by} ({self.status}) at {self.triggered_at}'
