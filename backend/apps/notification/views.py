from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.generics import CreateAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response

from .models import Device, Notification
from .serializers import (
    DeviceSerializer,
    NotificationSerializer,
    RegisterDeviceSerializer,
)


class NotificationViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        qs = Notification.objects.filter(user=self.request.user)
        is_read = self.request.query_params.get('is_read')
        if is_read is not None:
            qs = qs.filter(is_read=is_read.lower() == 'true')
        return qs

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = NotificationSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = NotificationSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=NotificationSerializer(instance).data)

    @action(detail=True, methods=['put'], url_path='read')
    def mark_read(self, request, pk=None):
        instance = self.get_object()
        instance.is_read = True
        instance.read_at = timezone.now()
        instance.save(update_fields=['is_read', 'read_at'])
        return success_response(data=NotificationSerializer(instance).data)

    @action(detail=False, methods=['put'], url_path='read-all')
    def mark_all_read(self, request):
        now = timezone.now()
        updated = Notification.objects.filter(
            user=request.user, is_read=False,
        ).update(is_read=True, read_at=now)
        return success_response(data={'updated_count': updated})


class DeviceView(CreateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = RegisterDeviceSerializer

    def create(self, request, *args, **kwargs):
        serializer = RegisterDeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        device, created = Device.objects.update_or_create(
            user=request.user,
            device_token=serializer.validated_data['device_token'],
            defaults={
                'platform': serializer.validated_data['platform'],
                'device_name': serializer.validated_data.get('device_name', ''),
                'is_active': True,
            },
        )
        return success_response(
            data=DeviceSerializer(device).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )
