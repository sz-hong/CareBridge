import uuid

from django.conf import settings
from django.db import models


class BoardRequest(models.Model):
    class Category(models.TextChoices):
        FOOD = 'food', 'Food'
        DAILY = 'daily', 'Daily'
        MEDICAL = 'medical', 'Medical'
        OTHER = 'other', 'Other'

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        APPROVED = 'approved', 'Approved'
        REJECTED = 'rejected', 'Rejected'
        COMPLETED = 'completed', 'Completed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='board_requests'
    )
    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='board_requests',
    )
    category = models.CharField(max_length=10, choices=Category.choices)
    items = models.JSONField()
    note = models.TextField(null=True, blank=True)
    note_translated = models.TextField(null=True, blank=True)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    reply = models.TextField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_board_requests',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'board_request'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['family', 'status'], name='idx_board_family_status'),
        ]

    def __str__(self):
        return f'{self.category} request by {self.requester} ({self.status})'
