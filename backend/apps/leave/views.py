from datetime import datetime

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response

from apps.calendar_event.models import Event
from .models import Leave
from .serializers import (
    CreateLeaveSerializer,
    LeaveSerializer,
    UpdateLeaveStatusSerializer,
)


class LeaveViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = LeaveSerializer

    def get_queryset(self):
        qs = Leave.objects.filter(family=self.request.user.family)
        s = self.request.query_params.get('status')
        if s:
            qs = qs.filter(status=s)
        return qs.select_related('applicant', 'reviewed_by', 'calendar_event')

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateLeaveSerializer
        return LeaveSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = LeaveSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = LeaveSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateLeaveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        start_date = serializer.validated_data['start_date']
        end_date = serializer.validated_data['end_date']
        days = (end_date - start_date).days + 1
        leave = serializer.save(
            family=request.user.family,
            applicant=request.user,
            days=days,
        )
        return success_response(
            data=LeaveSerializer(leave).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=LeaveSerializer(instance).data)

    @action(detail=True, methods=['patch'], url_path='status')
    def update_status(self, request, pk=None):
        instance = self.get_object()
        serializer = UpdateLeaveStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        new_status = serializer.validated_data['status']
        reply = serializer.validated_data.get('reply', '')

        instance.status = new_status
        instance.reply = reply
        instance.reviewed_by = request.user
        instance.reviewed_at = timezone.now()

        if new_status == 'approved':
            # Auto-create calendar event for the leave period
            event = Event.objects.create(
                family=instance.family,
                title=f'{instance.get_type_display()} Leave - {instance.applicant.name}',
                start_time=datetime.combine(instance.start_date, datetime.min.time()),
                end_time=datetime.combine(
                    instance.end_date, datetime.max.time().replace(microsecond=0),
                ),
                type=Event.Type.LEAVE,
                source=Event.Source.LEAVE,
                source_id=instance.id,
                note=instance.reason,
                created_by=request.user,
            )
            instance.calendar_event = event

        instance.save()
        return success_response(data=LeaveSerializer(instance).data)
