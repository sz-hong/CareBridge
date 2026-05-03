import string
import secrets

from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import error_response, success_response

from .models import Family
from .serializers import FamilySerializer, CreateFamilySerializer, JoinFamilySerializer


def generate_invite_code(length=6):
    while True:
        code = ''.join(secrets.choice(string.digits) for _ in range(length))
        if not Family.objects.filter(invite_code=code).exists():
            return code


class FamilyViewSet(ModelViewSet):
    serializer_class = FamilySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        if self.action == 'join':
            return Family.objects.all()

        family_id = getattr(self.request.user, 'family_id', None)
        if not family_id:
            return Family.objects.none()
        return Family.objects.filter(id=family_id)

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateFamilySerializer
        if self.action == 'join':
            return JoinFamilySerializer
        return FamilySerializer

    def create(self, request, *args, **kwargs):
        serializer = CreateFamilySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        family = serializer.save(
            invite_code=generate_invite_code(),
            created_by=request.user,
        )
        # Creator is always the primary family member
        request.user.family = family
        request.user.is_primary = True
        request.user.role = 'family_member'
        request.user.save(update_fields=['family', 'is_primary', 'role'])

        return success_response(
            data=FamilySerializer(family).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=FamilySerializer(instance).data)

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = FamilySerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(
                data=paginated.data.get('results', serializer.data),
                meta={
                    'count': paginated.data.get('count'),
                    'next': paginated.data.get('next'),
                    'previous': paginated.data.get('previous'),
                },
            )
        serializer = FamilySerializer(queryset, many=True)
        return success_response(data=serializer.data)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = FamilySerializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return success_response(data=serializer.data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(
            data={"detail": "Family deleted."},
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=['get'])
    def members(self, request):
        if not request.user.family:
            return success_response(data=[])
        
        from apps.auth_account.serializers import UserSerializer
        users = request.user.family.members.all()
        return success_response(data=UserSerializer(users, many=True).data)

    @action(detail=True, methods=['post'])
    def join(self, request, pk=None):
        serializer = JoinFamilySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        invite_code = serializer.validated_data['invite_code']
        family = self.get_object()

        if family.invite_code != invite_code:
            return error_response(
                code='invalid_invite',
                message='Invalid invite code.',
                status=status.HTTP_400_BAD_REQUEST,
            )

        request.user.family = family
        request.user.is_primary = False
        request.user.save(update_fields=['family', 'is_primary'])

        from apps.chat.services import enroll_user_in_family_chats
        enroll_user_in_family_chats(request.user)

        return success_response(data=FamilySerializer(family).data)

    @action(
        detail=True,
        methods=['delete'],
        url_path=r'members/(?P<user_id>[^/.]+)',
    )
    def remove_member(self, request, pk=None, user_id=None):
        family = self.get_object()
        try:
            from apps.auth_account.models import User
            member = User.objects.get(id=user_id, family=family)
        except User.DoesNotExist:
            return error_response(
                code='not_found',
                message='Member not found in this family.',
                status=status.HTTP_404_NOT_FOUND,
            )

        member.family = None
        member.is_primary = False
        member.save(update_fields=['family', 'is_primary'])

        return success_response(data={"detail": "Member removed."})
