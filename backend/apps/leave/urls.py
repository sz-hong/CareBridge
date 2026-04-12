from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import LeaveViewSet

router = DefaultRouter()
router.register('', LeaveViewSet, basename='leave')

urlpatterns = [
    path('', include(router.urls)),
]
