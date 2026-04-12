from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Document


class DocumentSerializer(serializers.ModelSerializer):
    uploaded_by = UserSerializer(read_only=True)

    class Meta:
        model = Document
        fields = [
            'id', 'family', 'title', 'category', 'file_url', 'file_size',
            'mime_type', 'uploaded_by', 'created_at',
        ]
        read_only_fields = fields


class CreateDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Document
        fields = ['title', 'category', 'file_url', 'file_size', 'mime_type']
