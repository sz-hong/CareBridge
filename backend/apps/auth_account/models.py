import uuid

from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    class Role(models.TextChoices):
        CAREGIVER = 'caregiver', 'Caregiver'
        FAMILY_MEMBER = 'family_member', 'Family Member'
        ELDER = 'elder', 'Elder'

    class Language(models.TextChoices):
        ZH_TW = 'zh-TW', '繁體中文'
        ID = 'id', 'Bahasa Indonesia'
        VI = 'vi', 'Tiếng Việt'
        TL = 'tl', 'Tagalog'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=150)
    role = models.CharField(max_length=20, choices=Role.choices)
    language = models.CharField(
        max_length=10, choices=Language.choices, default=Language.ZH_TW
    )
    phone = models.CharField(max_length=20, null=True, blank=True)
    avatar_url = models.URLField(max_length=500, null=True, blank=True)
    family = models.ForeignKey(
        'family.Family',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='members',
    )
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Remove username field; use email as the login identifier
    username = None
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['name']

    class Meta:
        db_table = 'user'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.email})'
