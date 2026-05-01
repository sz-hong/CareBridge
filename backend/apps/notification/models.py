import uuid

from django.conf import settings
from django.db import models

from .types import NotificationType


class Notification(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    type = models.CharField(max_length=30, choices=NotificationType.choices)
    title = models.CharField(max_length=200)
    title_translated = models.JSONField(null=True, blank=True)
    body = models.TextField()
    body_translated = models.JSONField(null=True, blank=True)
    data = models.JSONField(null=True, blank=True)
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'notification'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'is_read', '-created_at'], name='idx_notif_user_read'),
        ]

    def __str__(self):
        return f'{self.type}: {self.title} (to {self.user})'


class Device(models.Model):
    class Platform(models.TextChoices):
        IOS = 'ios', 'iOS'
        WATCHOS = 'watchos', 'watchOS'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='devices',
    )
    device_token = models.CharField(max_length=200)
    platform = models.CharField(max_length=10, choices=Platform.choices)
    device_name = models.CharField(max_length=100, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'device'
        unique_together = ('user', 'device_token')
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.device_name or self.platform} ({self.user})'
