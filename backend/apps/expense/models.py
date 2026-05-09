import uuid

from django.conf import settings
from django.db import models


class Expense(models.Model):
    class Status(models.TextChoices):
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'

    class DeidentificationStatus(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        NEEDS_REVIEW = 'needs_review', 'Needs Review'
        FAILED = 'failed', 'Failed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='expenses'
    )
    recorder = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='recorded_expenses',
    )
    scan_id = models.CharField(max_length=100, null=True, blank=True)
    store_name = models.CharField(max_length=200, null=True, blank=True)
    date = models.DateField()
    items = models.JSONField()
    total_amount = models.DecimalField(max_digits=10, decimal_places=2)
    image_url = models.URLField(max_length=500, null=True, blank=True)
    raw_image_key = models.CharField(max_length=500, null=True, blank=True)
    redacted_image_key = models.CharField(max_length=500, null=True, blank=True)
    deid_status = models.CharField(
        max_length=20,
        choices=DeidentificationStatus.choices,
        default=DeidentificationStatus.COMPLETED,
    )
    deid_findings = models.JSONField(default=list, blank=True)
    deid_processed_at = models.DateTimeField(null=True, blank=True)
    ocr_confidence = models.DecimalField(
        max_digits=3, decimal_places=2, null=True, blank=True
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.COMPLETED
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'expense'
        ordering = ['-date']
        indexes = [
            models.Index(fields=['family', '-date'], name='idx_expense_family_date'),
        ]

    def __str__(self):
        return f'{self.store_name or "Expense"} - {self.total_amount} ({self.date})'
