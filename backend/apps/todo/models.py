import uuid

from django.conf import settings
from django.db import models


class Todo(models.Model):
    class Priority(models.TextChoices):
        HIGH = 'high', 'High'
        MEDIUM = 'medium', 'Medium'
        LOW = 'low', 'Low'

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        COMPLETED = 'completed', 'Completed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='todos'
    )
    title = models.CharField(max_length=200)
    title_translated = models.JSONField(null=True, blank=True)
    assignee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='assigned_todos',
    )
    priority = models.CharField(
        max_length=10, choices=Priority.choices, default=Priority.MEDIUM
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    due_date = models.DateField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    care_log = models.ForeignKey(
        'care_log.CareLog',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='todos',
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='created_todos',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'todo'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['family', 'status'], name='idx_todo_family_status'),
            models.Index(fields=['assignee', 'status'], name='idx_todo_assignee'),
        ]

    def __str__(self):
        return f'{self.title} ({self.status})'
