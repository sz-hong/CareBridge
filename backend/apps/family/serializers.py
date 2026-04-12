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
    invite_code = serializers.CharField(max_length=8)
