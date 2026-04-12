import uuid

from django.conf import settings
from django.db import models


class AIConversation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='ai_conversations'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='ai_conversations',
    )
    messages_history = models.JSONField(default=list)
    tokens_used = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'ai_conversation'
        ordering = ['-updated_at']

    def __str__(self):
        return f'AI conversation by {self.user} ({self.created_at})'


class FirstAidDocument(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=300)
    source = models.CharField(max_length=200)
    section = models.CharField(max_length=200, null=True, blank=True)
    content = models.TextField()
    # In production, this should be a VECTOR(1024) column (e.g. using pgvector).
    # Using TextField as a placeholder for development environments.
    embedding = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'first_aid_document'
        ordering = ['title']

    def __str__(self):
        return self.title
