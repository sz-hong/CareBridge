from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import CareLogViewSet

router = DefaultRouter(trailing_slash=False)
router.register('', CareLogViewSet, basename='care-log')

urlpatterns = [
    path('', include(router.urls)),
]
