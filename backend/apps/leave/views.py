from datetime import datetime

from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.permissions import CaregiverCannotDelete
from core.responses import success_response
from core.viewsets import FamilyScopedQuerySetMixin

from apps.auth_account.models import User
from apps.calendar_event.models import Event
from apps.notification.types import NotificationType
from .models import Leave, LeaveVote
from .serializers import (
    CreateLeaveSerializer,
    CreateLeaveVoteSerializer,
    LeaveSerializer,
    UpdateLeaveStatusSerializer,
)


class LeaveViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]
    serializer_class = LeaveSerializer

    def get_queryset(self):
        qs = self.scope_queryset_to_family(Leave.objects.all())
        s = self.request.query_params.get('status')
        if s:
            qs = qs.filter(status=s)
        return qs.select_related(
            'applicant', 'reviewed_by', 'calendar_event',
        ).prefetch_related('votes')

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
            instance.calendar_event = self._ensure_calendar_event(
                instance, request.user,
            )

        instance.save()

        # Phase 7: Notify leave applicant of status change
        try:
            from apps.notification.tasks import send_notification_task
            status_label = 'Approved' if new_status == 'approved' else 'Rejected'
            send_notification_task.delay(
                user_id=str(instance.applicant.id),
                type=NotificationType.LEAVE_STATUS,
                title=f'Leave {status_label}',
                body=f'Your {instance.get_type_display()} leave has been {status_label.lower()}.',
                data={
                    'leave_id': str(instance.id),
                    'status': new_status,
                },
            )
        except Exception:
            import logging
            logging.getLogger(__name__).warning(
                'Failed to send leave notification', exc_info=True
            )

        return success_response(data=LeaveSerializer(instance).data)

    @action(detail=True, methods=['post'], url_path='vote')
    def vote(self, request, pk=None):
        """POST /leaves/{id}/vote/ — One family member votes available/not.

        Auto-resolves status once every family-role member has voted:
          • any vote is_available=True → approved
          • all votes is_available=False → rejected
        Re-voting overwrites the prior vote (unique_together on leave+member).
        """
        instance = self.get_object()
        ser = CreateLeaveVoteSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        with transaction.atomic():
            LeaveVote.objects.update_or_create(
                leave=instance,
                member=request.user,
                defaults={
                    'member_name': request.user.name or request.user.email,
                    'is_available': ser.validated_data['is_available'],
                },
            )
            self._maybe_resolve_status(instance, request.user)

        return success_response(data=LeaveSerializer(instance).data)

    def _maybe_resolve_status(self, leave, actor):
        """Resolve leave.status from the family's votes.

        Asymmetric short-circuit logic:
          • **Any** family-role member voting "available" (有空) → APPROVED
            immediately, no need to wait for the rest. Helps the leave
            request resolve as soon as a willing caregiver-substitute
            exists.
          • **All** family-role members voting "unavailable" (沒空) →
            REJECTED. Must wait for every eligible member to weigh in
            before rejecting, in case a later vote rescues it.
          • Otherwise → stays PENDING.

        Voting-eligible = users in this family with role=family_member
        (caregivers don't vote; they're the applicant on caregiver leaves).
        """
        if leave.status != Leave.Status.PENDING:
            return  # Already resolved — don't overwrite

        # Query LeaveVote directly to bypass any prefetch_related('votes')
        # cache on the leave instance — get_queryset prefetches votes for
        # list views, and that cached queryset wouldn't reflect the vote we
        # just created in the same request.
        votes = list(LeaveVote.objects.filter(leave=leave))

        if any(v.is_available for v in votes):
            leave.status = Leave.Status.APPROVED
        else:
            eligible_count = User.objects.filter(
                family=leave.family,
                role=User.Role.FAMILY_MEMBER,
            ).count()
            if len(votes) < eligible_count:
                return  # Still waiting on more "no" votes before rejecting
            leave.status = Leave.Status.REJECTED

        leave.reviewed_by = actor
        leave.reviewed_at = timezone.now()

        if leave.status == Leave.Status.APPROVED and not leave.calendar_event_id:
            leave.calendar_event = self._ensure_calendar_event(leave, actor)

        leave.save()

    def _ensure_calendar_event(self, leave, actor):
        if leave.calendar_event_id:
            return leave.calendar_event

        return Event.objects.create(
            family=leave.family,
            title=f'{leave.get_type_display()} Leave - {leave.applicant.name}',
            start_time=timezone.make_aware(
                datetime.combine(leave.start_date, datetime.min.time()),
            ),
            end_time=timezone.make_aware(
                datetime.combine(
                    leave.end_date,
                    datetime.max.time().replace(microsecond=0),
                ),
            ),
            type=Event.Type.LEAVE,
            source=Event.Source.LEAVE,
            source_id=leave.id,
            note=leave.reason,
            created_by=actor,
        )
