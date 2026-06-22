import uuid

from django.conf import settings
from django.db import models


class AdminMutationAuditLog(models.Model):
    class Action(models.TextChoices):
        CREATE = 'create', 'Create'
        UPDATE = 'update', 'Update'
        DELETE = 'delete', 'Delete'
        UPLOAD = 'upload', 'Upload'
        PRESIGN_PREVIEW = 'presign_preview', 'Presign preview'
        PRESIGN_DOWNLOAD = 'presign_download', 'Presign download'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    request_id = models.CharField(max_length=100, null=True, blank=True)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='admin_mutation_audit_logs',
    )
    actor_email = models.EmailField(null=True, blank=True)
    action = models.CharField(max_length=32, choices=Action.choices)
    table = models.CharField(max_length=64, null=True, blank=True)
    record_id = models.CharField(max_length=64, null=True, blank=True)
    bucket = models.CharField(max_length=255, null=True, blank=True)
    object_key = models.TextField(null=True, blank=True)
    status_code = models.PositiveSmallIntegerField(default=200)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'admin_mutation_audit_log'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['table', 'record_id'], name='idx_admin_audit_record'),
            models.Index(fields=['action', '-created_at'], name='idx_admin_audit_action'),
        ]


class AdminRequestLog(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    request_id = models.CharField(max_length=100, null=True, blank=True, db_index=True)
    method = models.CharField(max_length=10)
    path = models.TextField()
    query = models.TextField(blank=True, default='')
    status_code = models.PositiveSmallIntegerField()
    duration_ms = models.PositiveIntegerField(default=0)
    user_id = models.CharField(max_length=64, null=True, blank=True)
    user_email = models.EmailField(null=True, blank=True)
    is_staff = models.BooleanField(default=False)
    ip = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True, default='')
    error_code = models.CharField(max_length=100, null=True, blank=True)
    error_message = models.TextField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'admin_request_log'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['-created_at'], name='idx_admin_req_created'),
            models.Index(fields=['method', '-created_at'], name='idx_admin_req_method'),
            models.Index(fields=['status_code', '-created_at'], name='idx_admin_req_status'),
            models.Index(fields=['user_email', '-created_at'], name='idx_admin_req_user'),
        ]
