from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import HealthDataViewSet

router = DefaultRouter()
router.register('', HealthDataViewSet, basename='health-data')

urlpatterns = [
    path('', include(router.urls)),
]
