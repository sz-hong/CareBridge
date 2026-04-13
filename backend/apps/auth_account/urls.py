from django.urls import path

from .views import (
    RegisterView,
    LoginView,
    MeView,
    LogoutView,
    DeleteAccountView,
    JoinFamilyView,
)

urlpatterns = [
    path('register/', RegisterView.as_view(), name='auth-register'),
    path('login/', LoginView.as_view(), name='auth-login'),
    path('me/', MeView.as_view(), name='auth-me'),
    path('logout/', LogoutView.as_view(), name='auth-logout'),
    path('account/', DeleteAccountView.as_view(), name='auth-delete-account'),
    path('join-family/', JoinFamilyView.as_view(), name='auth-join-family'),
]
