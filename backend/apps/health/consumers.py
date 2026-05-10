"""WebSocket consumer for live health data updates.

Connect URL: ws://host/ws/health/?token=<JWT>
- Auth via the existing core.ws_auth.JWTAuthMiddleware (re-used from chat)
- Each user is auto-joined to a `health_{family_id}` channel layer group
- Backend `views.py` calls `broadcast_health_update(family, payload)` after
  every successful sync to push the new data points to all connected family
  members in real time.
"""
import json
import logging

from channels.generic.websocket import AsyncWebsocketConsumer

logger = logging.getLogger(__name__)


class HealthConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        user = self.scope.get('user')
        if not getattr(user, 'is_authenticated', False):
            await self.close(code=4401)
            return

        family_id = getattr(user, 'family_id', None)
        if not family_id:
            await self.close(code=4403)
            return

        self.group_name = f'health_{family_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(
                self.group_name, self.channel_name
            )

    async def health_update(self, event):
        """Re-emit the broadcast payload to the websocket client."""
        await self.send(text_data=json.dumps(event['payload']))
