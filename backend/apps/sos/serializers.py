from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import SOSRecord


class SOSRecordSerializer(serializers.ModelSerializer):
    triggered_by = UserSerializer(read_only=True)

    class Meta:
        model = SOSRecord
        fields = [
            'id', 'family', 'triggered_by', 'location', 'situation',
            'auto_call_119', 'notified_members', 'status',
            'triggered_at', 'resolved_at',
        ]
        read_only_fields = fields


class TriggerSOSSerializer(serializers.Serializer):
    location = serializers.JSONField(required=False)
    situation = serializers.CharField(required=False, allow_blank=True)
