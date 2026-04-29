from rest_framework import serializers

from apps.auth_account.models import User
from apps.chat.models import Chat, ChatMember, Message


class MemberUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'name', 'role', 'avatar_url']


class MessageSerializer(serializers.ModelSerializer):
    sender = MemberUserSerializer(read_only=True)
    is_me = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = [
            'id', 'chat', 'sender', 'is_me', 'type', 'message_type',
            'reference_id', 'content', 'translations', 'image_url', 'sent_at',
        ]
        read_only_fields = ['id', 'chat', 'sender', 'sent_at']

    def get_is_me(self, obj):
        request = self.context.get('request')
        if request and hasattr(request, 'user') and request.user.is_authenticated:
            return obj.sender_id == request.user.id
        return False


class SendMessageSerializer(serializers.Serializer):
    """
    Accepts the FE wire format where `type` carries either the legacy content
    encoding (text / image) or the new semantic intent (purchase_request /
    leave_request). The view dispatches to the right model fields based on
    `_REQUEST_TYPES`.
    """
    _CONTENT_TYPES = {'text', 'image'}
    _REQUEST_TYPES = {'purchase_request', 'leave_request'}

    type = serializers.CharField(default='text')
    content = serializers.CharField(required=False, allow_blank=True)
    image_url = serializers.URLField(required=False, allow_blank=True)
    reference_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_type(self, value):
        valid = self._CONTENT_TYPES | self._REQUEST_TYPES
        if value not in valid:
            raise serializers.ValidationError(
                f'Invalid type. Must be one of {sorted(valid)}.'
            )
        return value

    def validate(self, attrs):
        t = attrs.get('type', 'text')
        if t in self._REQUEST_TYPES:
            if not attrs.get('reference_id'):
                raise serializers.ValidationError(
                    {'reference_id': f'reference_id is required for {t}.'}
                )
            if not attrs.get('content'):
                raise serializers.ValidationError(
                    {'content': 'content is required.'}
                )
        elif t == 'text' and not attrs.get('content'):
            raise serializers.ValidationError(
                {'content': 'Content is required for text messages.'}
            )
        elif t == 'image' and not attrs.get('image_url'):
            raise serializers.ValidationError(
                {'image_url': 'image_url is required for image messages.'}
            )
        return attrs


class ChatSerializer(serializers.ModelSerializer):
    members = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = Chat
        fields = [
            'id', 'type', 'name', 'family', 'created_at',
            'members', 'last_message', 'unread_count',
        ]
        read_only_fields = ['id', 'created_at']

    def get_members(self, obj):
        memberships = obj.members.select_related('user').all()
        return MemberUserSerializer(
            [m.user for m in memberships], many=True
        ).data

    def get_last_message(self, obj):
        last = obj.messages.order_by('-sent_at').first()
        if last is None:
            return None
        return {
            'id': str(last.id),
            'content': last.content or '',
            'type': last.type,
            'sent_at': last.sent_at.isoformat(),
            'sender_id': str(last.sender_id),
        }

    def get_unread_count(self, obj):
        # Placeholder -- will be replaced when read-receipts are implemented
        return 0


class CreateChatSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=Chat.Type.choices)
    name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    family_id = serializers.UUIDField()
    member_ids = serializers.ListField(
        child=serializers.UUIDField(), min_length=1,
    )
