from rest_framework import status
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.permissions import CaregiverCannotDelete
from core.responses import empty_success_response, error_response, success_response
from core.translation import (
    translate_board_items,
    translate_for_user,
)
from core.viewsets import FamilyScopedQuerySetMixin

from .models import BoardRequest
from .serializers import BoardRequestSerializer, CreateBoardRequestSerializer


class BoardRequestViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]
    serializer_class = BoardRequestSerializer

    def get_queryset(self):
        qs = self.scope_queryset_to_family(BoardRequest.objects.all())
        s = self.request.query_params.get('status')
        if s:
            qs = qs.filter(status=s)
        return qs.select_related('requester', 'reviewed_by')

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateBoardRequestSerializer
        return BoardRequestSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = BoardRequestSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = BoardRequestSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateBoardRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        board_request = serializer.save(
            family=request.user.family,
            requester=request.user,
        )
        board_request.items = translate_board_items(
            board_request.items, user=request.user,
        )
        board_request.note_translations = translate_for_user(
            board_request.note or '',
            user=request.user,
            mode='mixed_text',
            protected_terms=_board_protected_terms(board_request, request.user),
        )
        board_request.save(update_fields=['items', 'note_translations', 'updated_at'])
        return success_response(
            data=BoardRequestSerializer(board_request).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=BoardRequestSerializer(instance).data)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        if _is_caregiver(request.user) or _is_caregiver(instance.requester):
            self._ensure_caregiver_owns_pending_request(request, instance)
        serializer = CreateBoardRequestSerializer(
            instance, data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        if 'items' in request.data:
            instance.items = translate_board_items(
                instance.items, user=request.user,
            )
        if 'note' in request.data:
            instance.note_translations = translate_for_user(
                instance.note or '',
                user=request.user,
                mode='mixed_text',
                protected_terms=_board_protected_terms(instance, request.user),
            )
        instance.save(update_fields=['items', 'note_translations', 'updated_at'])
        return success_response(data=BoardRequestSerializer(instance).data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        if _is_caregiver(request.user) or _is_caregiver(instance.requester):
            raise PermissionDenied('Use withdraw instead of deleting caregiver requests.')
        instance.delete()
        return empty_success_response()

    @action(detail=True, methods=['patch'], url_path='status')
    def update_status(self, request, pk=None):
        instance = self.get_object()
        new_status = request.data.get('status')
        reply = request.data.get('reply', '')

        if new_status not in ('approved', 'rejected', 'completed', 'withdrawn'):
            return error_response(
                code='invalid_status',
                message='Invalid status.',
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_status == BoardRequest.Status.WITHDRAWN:
            self._ensure_caregiver_owns_pending_request(request, instance)
            instance.status = BoardRequest.Status.WITHDRAWN
            instance.reply = ''
            instance.reply_translations = {}
            instance.reviewed_by = None
            instance.save(update_fields=[
                'status', 'reply', 'reply_translations', 'reviewed_by', 'updated_at',
            ])
            return success_response(data=BoardRequestSerializer(instance).data)

        if _is_caregiver(request.user):
            raise PermissionDenied('Caregivers cannot review purchase requests.')

        instance.status = new_status
        instance.reply = reply
        instance.reply_translations = translate_for_user(
            reply,
            user=request.user,
            mode='mixed_text',
            protected_terms=_board_protected_terms(instance, request.user),
        )
        instance.reviewed_by = request.user
        instance.save(update_fields=[
            'status', 'reply', 'reply_translations', 'reviewed_by', 'updated_at',
        ])
        return success_response(data=BoardRequestSerializer(instance).data)

    def _ensure_caregiver_owns_pending_request(self, request, instance):
        if not _is_caregiver(request.user) or instance.requester_id != request.user.id:
            raise PermissionDenied('Only the caregiver requester can modify this request.')
        if instance.status != BoardRequest.Status.PENDING:
            raise PermissionDenied('Only pending requests can be modified or withdrawn.')


def _is_caregiver(user):
    return getattr(user, 'role', None) == 'caregiver'


def _board_protected_terms(board_request, user):
    family = getattr(user, 'family', None)
    item_names = [
        item.get('name')
        for item in (board_request.items or [])
        if isinstance(item, dict)
    ]
    terms = [
        *item_names,
        getattr(user, 'name', None),
        getattr(family, 'name', None),
        getattr(family, 'elder_name', None),
    ]
    return [term for term in terms if term]
