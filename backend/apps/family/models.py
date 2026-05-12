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
    # Apple Health 同步綁定：同一個家庭只能有一支裝置往 /health-data/sync/
    # 推資料，避免兩支手機（同一個老人家、不同照護者裝置）同時推導致雜訊。
    # binding owner 的 sync 是被允許的；其他人會被 403 擋掉。
    health_binding_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='health_bound_families',
    )
    health_binding_device_id = models.CharField(max_length=64, blank=True, default='')
    health_binding_device_label = models.CharField(max_length=120, blank=True, default='')
    health_binding_claimed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'family'
        ordering = ['-created_at']
        verbose_name_plural = 'families'

    def __str__(self):
        return self.name
