from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import BoardRequest


class BoardRequestSerializer(serializers.ModelSerializer):
    requester = UserSerializer(read_only=True)

    class Meta:
        model = BoardRequest
        fields = [
            'id', 'family', 'requester', 'category', 'items', 'note',
            'note_translated', 'note_translations', 'status', 'reply',
            'reply_translations', 'reviewed_by', 'created_at', 'updated_at',
        ]
        read_only_fields = fields


class CreateBoardRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = BoardRequest
        fields = ['category', 'items', 'note']
