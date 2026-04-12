from rest_framework import serializers

from apps.auth_account.models import User
from apps.chat.models import Chat, ChatMember, Message


class MemberUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'name', 'role', 'avatar_url']


class MessageSerializer(serializers.ModelSerializer):
    sender = MemberUserSerializer(read_only=True)

    class Meta:
        model = Message
        fields = [
            'id', 'chat', 'sender', 'type', 'content',
            'translations', 'image_url', 'sent_at',
        ]
        read_only_fields = ['id', 'chat', 'sender', 'sent_at']


class SendMessageSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=Message.Type.choices, default='text')
    content = serializers.CharField(required=False, allow_blank=True)
    image_url = serializers.URLField(required=False, allow_blank=True)

    def validate(self, attrs):
        msg_type = attrs.get('type', 'text')
        if msg_type == 'text' and not attrs.get('content'):
            raise serializers.ValidationError(
                {'content': 'Content is required for text messages.'}
            )
        if msg_type == 'image' and not attrs.get('image_url'):
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
