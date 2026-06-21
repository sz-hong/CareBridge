from rest_framework import serializers

from core.storage import generate_download_url
from .models import CareLog


class RecorderMiniSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()


class CareLogSerializer(serializers.ModelSerializer):
    recorder = RecorderMiniSerializer(read_only=True)
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = CareLog
        fields = [
            'id', 'family', 'recorder', 'type', 'content', 'content_translated',
            'photo_url', 'timestamp', 'created_at',
        ]
        read_only_fields = fields

    def get_photo_url(self, obj):
        if not obj.photo_key:
            return None
        try:
            return generate_download_url(obj.photo_key)
        except Exception:
            return None


class CreateCareLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = CareLog
        fields = ['type', 'content', 'photo_key', 'timestamp']
        extra_kwargs = {
            'photo_key': {
                'required': False,
                'allow_null': True,
                'allow_blank': True,
                'write_only': True,
            },
        }

    def validate(self, attrs):
        if 'photo_url' in self.initial_data:
            raise serializers.ValidationError({
                'photo_url': (
                    'Direct care-log photo URLs are disabled. '
                    'Upload through upload-url and send photo_key.'
                ),
            })
        return attrs
