import json
import logging

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

logger = logging.getLogger(__name__)


class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        # Auth is established by core.ws_auth.JWTAuthMiddleware (sets scope['user']).
        # Mirror HealthConsumer: reject anonymous (4401) and non-members (4403)
        # before accepting, so an unauthenticated or foreign client can never
        # join a chat group or spoof a sender.
        user = self.scope.get('user')
        if not getattr(user, 'is_authenticated', False):
            await self.close(code=4401)
            return

        self.chat_id = self.scope['url_route']['kwargs']['chat_id']

        if not await self.user_is_chat_member(user.id, self.chat_id):
            await self.close(code=4403)
            return

        self.user = user
        self.room_group_name = f'chat_{self.chat_id}'
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        # `room_group_name` is only set once a connection is accepted; guard so a
        # rejected handshake (4401/4403) does not raise on disconnect.
        if hasattr(self, 'room_group_name'):
            await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        data = json.loads(text_data)
        message_type = data.get('type', 'chat.message')

        if message_type == 'chat.message':
            # Sender is always the authenticated scope user established at
            # connect time; never trust a client-supplied sender_id.
            user_id = self.user.id

            # Save message, translate, and serialize using the same shape
            # as the REST MessageSerializer so the frontend has one codepath.
            payload = await self.save_translate_and_serialize(data, user_id)
            if payload is None:
                return

            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    'type': 'chat_message',
                    'message': payload,
                },
            )
        elif message_type == 'chat.typing':
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    'type': 'chat_typing',
                    'user_id': str(data.get('user_id', '')),
                    'is_typing': data.get('is_typing', False),
                },
            )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps(event['message']))

    async def chat_typing(self, event):
        await self.send(text_data=json.dumps({
            'type': 'typing',
            'user_id': event['user_id'],
            'is_typing': event['is_typing'],
        }))

    @database_sync_to_async
    def user_is_chat_member(self, user_id, chat_id):
        from apps.chat.models import ChatMember
        return ChatMember.objects.filter(
            chat_id=chat_id, user_id=user_id
        ).exists()

    @database_sync_to_async
    def save_translate_and_serialize(self, data, user_id):
        from apps.auth_account.models import User
        from apps.chat.models import Message
        from apps.chat.serializers import MessageSerializer
        from apps.chat.views import ChatViewSet

        if not user_id:
            return None

        try:
            sender = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return None

        # Mirror the REST dispatch: wire `message_type` (or legacy fallback)
        # routes either to Message.type (text/image) or Message.message_type
        # (purchase_request/leave_request) + reference_id.
        wire_type = data.get('message_type') or data.get('type') or 'text'
        if wire_type in ('purchase_request', 'leave_request'):
            message = Message.objects.create(
                chat_id=self.chat_id,
                sender=sender,
                type=Message.Type.TEXT,
                message_type=wire_type,
                reference_id=data.get('reference_id'),
                content=data.get('content', ''),
            )
        else:
            message = Message.objects.create(
                chat_id=self.chat_id,
                sender=sender,
                type=wire_type if wire_type in ('text', 'image') else 'text',
                message_type=Message.MessageType.TEXT,
                content=data.get('content', ''),
            )

        # Skip translation for request-card messages — content is structured
        # (emoji + Chinese label + dates) and the FE renders its own labels.
        if (
            message.type == Message.Type.TEXT
            and message.message_type == Message.MessageType.TEXT
            and message.content
        ):
            try:
                ChatViewSet._translate_message(message, sender)
            except Exception:
                logger.exception(
                    'WebSocket translation failed for message %s', message.id
                )

        message.refresh_from_db()
        # Round-trip through json.dumps(default=str) so UUIDs/datetimes become
        # strings; the channel layer's msgpack packer can't serialize them.
        return json.loads(json.dumps(MessageSerializer(message).data, default=str))
