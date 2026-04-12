from django.contrib import admin

from .models import Device, Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ('title', 'type', 'user', 'is_read', 'created_at')
    list_filter = ('type', 'is_read', 'created_at')
    search_fields = ('title', 'body', 'user__name', 'user__email')
    readonly_fields = ('id', 'created_at')


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ('device_name', 'platform', 'user', 'is_active', 'created_at')
    list_filter = ('platform', 'is_active', 'created_at')
    search_fields = ('device_name', 'device_token', 'user__name', 'user__email')
    readonly_fields = ('id', 'created_at', 'updated_at')
