from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Family


class FamilySerializer(serializers.ModelSerializer):
    members = UserSerializer(many=True, read_only=True)

    class Meta:
        model = Family
        fields = [
            'id', 'name', 'elder_name', 'elder_birth_date',
            'invite_code', 'created_by', 'created_at', 'members',
        ]
        read_only_fields = ['id', 'invite_code', 'created_by', 'created_at', 'members']


class CreateFamilySerializer(serializers.ModelSerializer):
    class Meta:
        model = Family
        fields = ['name', 'elder_name', 'elder_birth_date']


class JoinFamilySerializer(serializers.Serializer):
    invite_code = serializers.CharField(max_length=6)


class HealthBindingSerializer(serializers.Serializer):
    """Canonical representation of a family's health-sync binding state.

    Returned by every method on the binding endpoint so the client can
    refresh its local state from a single shape regardless of whether
    the call was a read, claim, or release.
    """

    is_bound = serializers.BooleanField()
    is_owner = serializers.BooleanField()
    user_id = serializers.CharField(allow_null=True)
    user_name = serializers.CharField(allow_null=True)
    device_id = serializers.CharField(allow_null=True)
    device_label = serializers.CharField(allow_null=True)
    claimed_at = serializers.DateTimeField(allow_null=True)


class ClaimHealthBindingSerializer(serializers.Serializer):
    device_id = serializers.CharField(max_length=64)
    device_label = serializers.CharField(max_length=120, required=False, allow_blank=True)
