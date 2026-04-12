from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response

from .models import Event
from .serializers import CreateEventSerializer, EventSerializer


class EventViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = EventSerializer
    pagination_class = None

    def get_queryset(self):
        qs = Event.objects.filter(family=self.request.user.family)
        event_type = self.request.query_params.get('type')
        if event_type:
            qs = qs.filter(type=event_type)
        start_after = self.request.query_params.get('start_after')
        if start_after:
            qs = qs.filter(start_time__gte=start_after)
        start_before = self.request.query_params.get('start_before')
        if start_before:
            qs = qs.filter(start_time__lte=start_before)
        return qs.select_related('created_by')

    def get_serializer_class(self):
        if self.action in ('create', 'update', 'partial_update'):
            return CreateEventSerializer
        return EventSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = EventSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = EventSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateEventSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        event = serializer.save(
            family=request.user.family,
            created_by=request.user,
        )
        return success_response(
            data=EventSerializer(event).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=EventSerializer(instance).data)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = CreateEventSerializer(
            instance, data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return success_response(data=EventSerializer(instance).data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False, methods=['post'], url_path='batch')
    def batch_create(self, request):
        items = request.data if isinstance(request.data, list) else request.data.get('events', [])
        created = []
        for item_data in items:
            serializer = CreateEventSerializer(data=item_data)
            serializer.is_valid(raise_exception=True)
            event = serializer.save(
                family=request.user.family,
                created_by=request.user,
            )
            created.append(EventSerializer(event).data)
        return success_response(data=created, status=status.HTTP_201_CREATED)
