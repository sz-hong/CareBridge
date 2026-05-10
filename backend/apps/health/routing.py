"""WebSocket URL routing for the health app."""
from django.urls import path

from .consumers import HealthConsumer

websocket_urlpatterns = [
    path('ws/health/', HealthConsumer.as_asgi()),
]
