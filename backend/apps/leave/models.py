import uuid

from django.conf import settings
from django.db import models


class Leave(models.Model):
    class Type(models.TextChoices):
        PERSONAL = 'personal', 'Personal'
        SICK = 'sick', 'Sick'
        EMERGENCY = 'emergency', 'Emergency'

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        APPROVED = 'approved', 'Approved'
        REJECTED = 'rejected', 'Rejected'
        WITHDRAWN = 'withdrawn', 'Withdrawn'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='leaves'
    )
    applicant = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='leaves',
    )
    type = models.CharField(max_length=20, choices=Type.choices)
    start_date = models.DateField()
    end_date = models.DateField()
    days = models.IntegerField()
    reason = models.TextField()
    reason_translated = models.TextField(null=True, blank=True)
    reason_translations = models.JSONField(null=True, blank=True)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    reply = models.TextField(null=True, blank=True)
    reply_translations = models.JSONField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_leaves',
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    calendar_event = models.ForeignKey(
        'calendar_event.Event',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='leaves',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'leave'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['family', 'status'], name='idx_leave_family_status'),
        ]

    def __str__(self):
        return f'{self.type} leave by {self.applicant} ({self.status})'


class LeaveVote(models.Model):
    """One vote cast by a family member on a leave request.

    Status auto-resolves once every family-role member has voted: if anyone
    voted available → approved; if all voted unavailable → rejected.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    leave = models.ForeignKey(
        Leave, on_delete=models.CASCADE, related_name='votes'
    )
    member = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='leave_votes',
    )
    # Snapshot of the voter's name at vote time so historical records stay
    # readable even if the user later renames or leaves the family.
    member_name = models.CharField(max_length=100)
    is_available = models.BooleanField()
    voted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'leave_vote'
        unique_together = ('leave', 'member')
        ordering = ['voted_at']

    def __str__(self):
        verdict = 'available' if self.is_available else 'unavailable'
        return f'{self.member_name} → {verdict} on {self.leave_id}'
