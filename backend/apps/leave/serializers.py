from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Leave


class LeaveSerializer(serializers.ModelSerializer):
    applicant = UserSerializer(read_only=True)

    class Meta:
        model = Leave
        fields = [
            'id', 'family', 'applicant', 'type', 'start_date', 'end_date',
            'days', 'reason', 'reason_translated', 'status', 'reply',
            'reviewed_by', 'reviewed_at', 'calendar_event', 'created_at',
        ]
        read_only_fields = fields


class CreateLeaveSerializer(serializers.ModelSerializer):
    class Meta:
        model = Leave
        fields = ['type', 'start_date', 'end_date', 'reason']


class UpdateLeaveStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=['approved', 'rejected'])
    reply = serializers.CharField(required=False, allow_blank=True)
