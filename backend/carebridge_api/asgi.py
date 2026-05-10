"""
ASGI config for carebridge_api project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/6.0/howto/deployment/asgi/
"""

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'carebridge_api.settings')

django_asgi_app = get_asgi_application()

from apps.chat.routing import websocket_urlpatterns as chat_ws_urlpatterns
from apps.health.routing import websocket_urlpatterns as health_ws_urlpatterns
from core.ws_auth import JWTAuthMiddleware

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": JWTAuthMiddleware(
        URLRouter(chat_ws_urlpatterns + health_ws_urlpatterns),
    ),
})
