from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import BoardRequest


class BoardRequestSerializer(serializers.ModelSerializer):
    requester = UserSerializer(read_only=True)
    note_translated = serializers.SerializerMethodField()

    def get_note_translated(self, obj):
        return _translated_for_reader(
            obj.note or '',
            obj.note_translations,
            getattr(obj, 'note_translated', None),
            self.context,
        )


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


def _translated_for_reader(original, translations, legacy_value, context):
    request = context.get('request') if context else None
    language = getattr(getattr(request, 'user', None), 'language', None) or 'zh-TW'
    if isinstance(translations, dict):
        translated = translations.get(language)
        if translated:
            return translated
    return legacy_value or original
