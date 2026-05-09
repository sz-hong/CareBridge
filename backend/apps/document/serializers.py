from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from core.storage import extract_key_from_url, generate_download_url
from .models import Document


class DocumentSerializer(serializers.ModelSerializer):
    uploaded_by = UserSerializer(read_only=True)
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = Document
        fields = [
            'id', 'family', 'title', 'category', 'file_url', 'file_size',
            'mime_type', 'deid_status', 'deid_findings', 'deid_processed_at',
            'uploaded_by', 'created_at',
        ]
        read_only_fields = fields

    def get_file_url(self, obj):
        if not obj.file_url:
            return None
        key = extract_key_from_url(obj.file_url)
        if not key:
            return obj.file_url
        try:
            return generate_download_url(key)
        except Exception:
            return obj.file_url


class CreateDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Document
        fields = [
            'title', 'category', 'file_url', 'file_size', 'mime_type',
            'raw_file_key',
        ]
        extra_kwargs = {
            'file_url': {'required': False, 'allow_null': True, 'allow_blank': True},
            'raw_file_key': {'required': False, 'allow_null': True, 'allow_blank': True},
        }
