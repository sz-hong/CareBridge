from rest_framework import serializers

from .models import Device, Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            'id', 'user', 'type', 'title', 'title_translated', 'body',
            'body_translated', 'data', 'is_read', 'read_at', 'created_at',
        ]
        read_only_fields = fields


class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = [
            'id', 'user', 'device_token', 'platform', 'device_name',
            'is_active', 'created_at', 'updated_at',
        ]
        read_only_fields = fields


class RegisterDeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ['device_token', 'platform', 'device_name']
