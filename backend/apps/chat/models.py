import uuid

from django.conf import settings
from django.db import models


class Chat(models.Model):
    class Type(models.TextChoices):
        GROUP = 'group', 'Group'
        DIRECT = 'direct', 'Direct'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    type = models.CharField(max_length=10, choices=Type.choices)
    name = models.CharField(max_length=100, null=True, blank=True)
    family = models.ForeignKey(
        'family.Family', on_delete=models.CASCADE, related_name='chats'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'chat'
        ordering = ['-created_at']

    def __str__(self):
        return self.name or f'{self.type} chat ({self.id})'


class ChatMember(models.Model):
    id = models.BigAutoField(primary_key=True)
    chat = models.ForeignKey(
        Chat, on_delete=models.CASCADE, related_name='members'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='chat_memberships',
    )
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'chat_member'
        unique_together = ('chat', 'user')
        ordering = ['-joined_at']

    def __str__(self):
        return f'{self.user} in {self.chat}'


class Message(models.Model):
    class Type(models.TextChoices):
        TEXT = 'text', 'Text'
        IMAGE = 'image', 'Image'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    chat = models.ForeignKey(
        Chat, on_delete=models.CASCADE, related_name='messages'
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    type = models.CharField(max_length=10, choices=Type.choices)
    content = models.TextField(null=True, blank=True)
    translations = models.JSONField(null=True, blank=True)
    image_url = models.URLField(max_length=500, null=True, blank=True)
    sent_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'message'
        ordering = ['sent_at']
        indexes = [
            models.Index(fields=['chat', '-sent_at'], name='idx_messages_chat_time'),
        ]

    def __str__(self):
        return f'Message by {self.sender} at {self.sent_at}'
