from rest_framework import status
from rest_framework.generics import CreateAPIView, RetrieveUpdateAPIView, DestroyAPIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError

from apps.family.models import Family
from core.responses import success_response

from .models import User
from .serializers import (
    UserSerializer,
    RegisterSerializer,
    LoginSerializer,
    UpdateProfileSerializer,
)


def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


class RegisterView(CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return success_response(
            data={
                "user": UserSerializer(user).data,
                "tokens": get_tokens_for_user(user),
            },
            status=status.HTTP_201_CREATED,
        )


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        return success_response(
            data={
                "user": UserSerializer(user).data,
                "tokens": get_tokens_for_user(user),
            }
        )


class MeView(RetrieveUpdateAPIView):
    permission_classes = [IsAuthenticated]

    def get_object(self):
        return self.request.user

    def get_serializer_class(self):
        if self.request.method in ('PUT', 'PATCH'):
            return UpdateProfileSerializer
        return UserSerializer

    def retrieve(self, request, *args, **kwargs):
        serializer = UserSerializer(self.get_object())
        return success_response(data=serializer.data)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = UpdateProfileSerializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return success_response(data=UserSerializer(instance).data)


class JoinFamilyView(APIView):
    """Join a family by invite code. Returns refreshed AuthResponse {user, tokens}."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        code = str(request.data.get("invite_code", "")).strip()
        role = str(request.data.get("role", "")).strip()

        if not code or len(code) != 6 or not code.isdigit():
            return Response(
                {"success": False, "error": {"code": "INVALID_INVITE", "message": "邀請碼須為 6 位數字"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if role not in ("caregiver", "family_member"):
            return Response(
                {"success": False, "error": {"code": "INVALID_ROLE", "message": "請選擇身份"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            family = Family.objects.get(invite_code=code)
        except Family.DoesNotExist:
            return Response(
                {"success": False, "error": {"code": "INVALID_INVITE", "message": "邀請碼無效"}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = request.user
        user.family = family
        user.role = role
        if user.is_primary and family.created_by_id != user.id:
            user.is_primary = False
        user.save(update_fields=["family", "is_primary", "role"])

        # Auto-add the joiner to every existing chat in this family. Without
        # this, ChatViewSet.get_queryset() filters by members__user= and
        # the new user sees an empty chat list despite being in the family.
        from apps.chat.services import enroll_user_in_family_chats
        enroll_user_in_family_chats(user)

        return success_response(data={
            "user": UserSerializer(user).data,
            "tokens": get_tokens_for_user(user),
        })


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if refresh_token:
            try:
                token = RefreshToken(refresh_token)
                token.blacklist()
            except (TokenError, AttributeError):
                # Token invalid or blacklist app not installed — still return success
                pass
        return success_response(data={"detail": "Successfully logged out."})


class DeleteAccountView(DestroyAPIView):
    permission_classes = [IsAuthenticated]

    def get_object(self):
        return self.request.user

    def destroy(self, request, *args, **kwargs):
        user = self.get_object()
        user.delete()
        return success_response(
            data={"detail": "Account deleted."},
            status=status.HTTP_200_OK,
        )
