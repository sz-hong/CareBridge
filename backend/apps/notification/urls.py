from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import DeviceView, NotificationViewSet

router = DefaultRouter()
router.register('', NotificationViewSet, basename='notification')

urlpatterns = [
    path('device/', DeviceView.as_view(), name='register-device'),
    path('', include(router.urls)),
]
