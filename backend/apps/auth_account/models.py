import uuid

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models


class UserManager(BaseUserManager):
    """Custom manager for email-based authentication (no username)."""

    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        extra_fields.setdefault('role', 'family_member')

        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True.')

        return self.create_user(email, password, **extra_fields)


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
    role = models.CharField(max_length=20, choices=Role.choices, null=True, blank=True)
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

    objects = UserManager()

    class Meta:
        db_table = 'user'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.email})'
