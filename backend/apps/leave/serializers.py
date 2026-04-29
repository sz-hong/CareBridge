from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Leave, LeaveVote


class LeaveVoteSerializer(serializers.ModelSerializer):
    member_id = serializers.UUIDField(source='member.id', read_only=True)

    class Meta:
        model = LeaveVote
        fields = ['id', 'member_id', 'member_name', 'is_available', 'voted_at']
        read_only_fields = fields


class LeaveSerializer(serializers.ModelSerializer):
    applicant = UserSerializer(read_only=True)
    applicant_name = serializers.CharField(source='applicant.name', read_only=True)
    votes = LeaveVoteSerializer(many=True, read_only=True)

    class Meta:
        model = Leave
        fields = [
            'id', 'family', 'applicant', 'applicant_name', 'type',
            'start_date', 'end_date', 'days', 'reason', 'reason_translated',
            'status', 'reply', 'reviewed_by', 'reviewed_at', 'calendar_event',
            'votes', 'created_at',
        ]
        read_only_fields = fields


class CreateLeaveSerializer(serializers.ModelSerializer):
    class Meta:
        model = Leave
        fields = ['type', 'start_date', 'end_date', 'reason']


class UpdateLeaveStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=['approved', 'rejected'])
    reply = serializers.CharField(required=False, allow_blank=True)


class CreateLeaveVoteSerializer(serializers.Serializer):
    is_available = serializers.BooleanField()
