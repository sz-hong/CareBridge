import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer


class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.chat_id = self.scope['url_route']['kwargs']['chat_id']
        self.room_group_name = f'chat_{self.chat_id}'
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        data = json.loads(text_data)
        message_type = data.get('type', 'chat.message')

        if message_type == 'chat.message':
            # Save message to DB
            message = await self.save_message(data)
            # Broadcast to group
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    'type': 'chat_message',
                    'message': message,
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
    def save_message(self, data):
        from apps.chat.models import Message

        message = Message.objects.create(
            chat_id=self.chat_id,
            sender_id=data.get('sender_id'),
            type=data.get('message_type', 'text'),
            content=data.get('content', ''),
        )
        return {
            'id': str(message.id),
            'chat_id': str(message.chat_id),
            'sender_id': str(message.sender_id),
            'type': message.type,
            'content': message.content,
            'sent_at': message.sent_at.isoformat(),
        }
