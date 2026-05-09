import uuid

from django.conf import settings
from django.db import models


class Document(models.Model):
    class Category(models.TextChoices):
        INSURANCE = 'insurance', 'Insurance'
        MEDICAL = 'medical', 'Medical'
        ID_DOCUMENT = 'id_document', 'ID Document'
        CONTRACT = 'contract', 'Contract'
        OTHER = 'other', 'Other'

    class DeidentificationStatus(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        NEEDS_REVIEW = 'needs_review', 'Needs Review'
        FAILED = 'failed', 'Failed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='documents'
    )
    title = models.CharField(max_length=200)
    category = models.CharField(max_length=20, choices=Category.choices)
    file_url = models.URLField(max_length=500, null=True, blank=True)
    file_size = models.IntegerField()
    mime_type = models.CharField(max_length=50)
    raw_file_key = models.CharField(max_length=500, null=True, blank=True)
    redacted_file_key = models.CharField(max_length=500, null=True, blank=True)
    deid_status = models.CharField(
        max_length=20,
        choices=DeidentificationStatus.choices,
        default=DeidentificationStatus.COMPLETED,
    )
    deid_findings = models.JSONField(default=list, blank=True)
    deid_processed_at = models.DateTimeField(null=True, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='uploaded_documents',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'document'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.title} ({self.category})'
