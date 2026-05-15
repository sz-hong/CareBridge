from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import CareLog


class RecorderMiniSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()


class CareLogSerializer(serializers.ModelSerializer):
    recorder = RecorderMiniSerializer(read_only=True)

    class Meta:
        model = CareLog
        fields = [
            'id', 'family', 'recorder', 'type', 'content', 'content_translated',
            'photo_url', 'timestamp', 'created_at',
        ]
        read_only_fields = fields


class CreateCareLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = CareLog
        fields = ['type', 'content', 'photo_url', 'timestamp']
