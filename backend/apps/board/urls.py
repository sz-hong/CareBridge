from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import BoardRequestViewSet

router = DefaultRouter()
router.register('', BoardRequestViewSet, basename='board-request')

urlpatterns = [
    path('', include(router.urls)),
]
