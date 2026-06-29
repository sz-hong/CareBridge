import hashlib
import uuid

from django.conf import settings
from django.db import models
from pgvector.django import HnswIndex, VectorField


FIRST_AID_EMBEDDING_DIMENSIONS = 1536


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
    embedding = VectorField(
        dimensions=FIRST_AID_EMBEDDING_DIMENSIONS,
        null=True,
        blank=True,
    )
    embedding_model = models.CharField(max_length=100, blank=True, default='')
    embedding_content_hash = models.CharField(max_length=64, blank=True, default='')
    embedded_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'first_aid_document'
        ordering = ['title']
        indexes = [
            HnswIndex(
                name='first_aid_embed_hnsw',
                fields=['embedding'],
                m=16,
                ef_construction=64,
                opclasses=['vector_cosine_ops'],
            ),
        ]

    def __str__(self):
        return self.title

    def embedding_source_text(self):
        parts = [self.title, self.section or '', self.content]
        return "\n".join(part.strip() for part in parts if part and part.strip())

    def embedding_source_hash_value(self):
        return hashlib.sha256(
            self.embedding_source_text().encode('utf-8')
        ).hexdigest()

    def needs_embedding_refresh(self, model_name):
        return (
            self.embedding is None
            or self.embedding_model != model_name
            or self.embedding_content_hash != self.embedding_source_hash_value()
        )
