from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path

from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)


def health_check(request):
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path('admin/', admin.site.urls),

    # JWT authentication
    path('api/v1/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # Health check
    path('api/v1/health/', health_check, name='health_check'),

    # App endpoints
    path('api/v1/auth/', include('apps.auth_account.urls')),
    path('api/v1/families/', include('apps.family.urls')),
    path('api/v1/chats/', include('apps.chat.urls')),
    path('api/v1/board/', include('apps.board.urls')),
    path('api/v1/care-logs/', include('apps.care_log.urls')),
    path('api/v1/medications/', include('apps.medication.urls')),
    path('api/v1/expenses/', include('apps.expense.urls')),
    path('api/v1/leaves/', include('apps.leave.urls')),
    path('api/v1/health-data/', include('apps.health.urls')),
    path('api/v1/events/', include('apps.calendar_event.urls')),
    path('api/v1/todos/', include('apps.todo.urls')),
    path('api/v1/documents/', include('apps.document.urls')),
    path('api/v1/ai/', include('apps.ai_assistant.urls')),
    path('api/v1/sos/', include('apps.sos.urls')),
    path('api/v1/notifications/', include('apps.notification.urls')),
]
