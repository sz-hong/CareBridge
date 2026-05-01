from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import empty_success_response, success_response
from core.viewsets import FamilyScopedQuerySetMixin

from .models import BoardRequest
from .serializers import BoardRequestSerializer, CreateBoardRequestSerializer


class BoardRequestViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated]
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
        return success_response(
            data=BoardRequestSerializer(board_request).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=BoardRequestSerializer(instance).data)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = CreateBoardRequestSerializer(
            instance, data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return success_response(data=BoardRequestSerializer(instance).data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return empty_success_response()

    @action(detail=True, methods=['patch'], url_path='status')
    def update_status(self, request, pk=None):
        instance = self.get_object()
        new_status = request.data.get('status')
        reply = request.data.get('reply', '')

        if new_status not in ('approved', 'rejected', 'completed'):
            return success_response(
                data={'detail': 'Invalid status.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        instance.status = new_status
        instance.reply = reply
        instance.reviewed_by = request.user
        instance.save(update_fields=['status', 'reply', 'reviewed_by', 'updated_at'])
        return success_response(data=BoardRequestSerializer(instance).data)
