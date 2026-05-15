from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Event


class EventSerializer(serializers.ModelSerializer):
    created_by = UserSerializer(read_only=True)

    class Meta:
        model = Event
        fields = [
            'id', 'family', 'title', 'title_translated', 'start_time',
            'end_time', 'location', 'type', 'reminder_minutes', 'note',
            'note_translated', 'source', 'source_id', 'created_by', 'created_at',
        ]
        read_only_fields = fields


class CreateEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = Event
        fields = [
            'title', 'start_time', 'end_time', 'location', 'type',
            'reminder_minutes', 'note',
        ]
