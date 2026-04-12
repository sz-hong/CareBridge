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

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='documents'
    )
    title = models.CharField(max_length=200)
    category = models.CharField(max_length=20, choices=Category.choices)
    file_url = models.URLField(max_length=500)
    file_size = models.IntegerField()
    mime_type = models.CharField(max_length=50)
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
