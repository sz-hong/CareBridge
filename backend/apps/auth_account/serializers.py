from django.contrib.auth import authenticate
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

from .models import User


class UserSerializer(serializers.ModelSerializer):
    family_name = serializers.SerializerMethodField()
    family_invite_code = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'name', 'role', 'language', 'phone',
            'avatar_url', 'family_id', 'family_name', 'family_invite_code',
            'is_primary', 'created_at',
        ]
        read_only_fields = fields

    def get_family_name(self, obj):
        if obj.family:
            return obj.family.name
        return None

    def get_family_invite_code(self, obj):
        if obj.family:
            return obj.family.invite_code
        return None


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    name = serializers.CharField(max_length=150)
    language = serializers.ChoiceField(
        choices=User.Language.choices, default=User.Language.ZH_TW
    )
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True)

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return value.lower()

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs.get('email', '').lower()
        password = attrs.get('password')

        user = authenticate(
            request=self.context.get('request'),
            email=email,
            password=password,
        )
        if not user:
            raise serializers.ValidationError('Invalid email or password.')

        attrs['user'] = user
        return attrs


class UpdateProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['name', 'language', 'phone', 'avatar_url']
        extra_kwargs = {
            'name': {'required': False},
            'language': {'required': False},
            'phone': {'required': False},
            'avatar_url': {'required': False},
        }


class ForgotPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField()


class ResetPasswordSerializer(serializers.Serializer):
    token = serializers.CharField()
    new_password = serializers.CharField(min_length=8)
