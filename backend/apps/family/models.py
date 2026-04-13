import uuid

from django.conf import settings
from django.db import models


class Family(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    elder_name = models.CharField(max_length=100)
    elder_birth_date = models.DateField(null=True, blank=True)
    invite_code = models.CharField(max_length=6, unique=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_families',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'family'
        ordering = ['-created_at']
        verbose_name_plural = 'families'

    def __str__(self):
        return self.name
