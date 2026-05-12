from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .health_binding_views import FamilyHealthBindingView
from .views import FamilyViewSet

router = DefaultRouter()
router.register('', FamilyViewSet, basename='family')

urlpatterns = [
    # 必須放在 router include 之前 —— 否則 `me/health-binding/` 會被
    # FamilyViewSet 的 detail route `(?P<pk>[^/.]+)/` 吃掉。
    path('me/health-binding/', FamilyHealthBindingView.as_view(), name='family-health-binding'),
    path('', include(router.urls)),
]
