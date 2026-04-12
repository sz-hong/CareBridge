import logging

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ViewSet

from core.responses import success_response

from .models import SOSRecord
from .serializers import SOSRecordSerializer, TriggerSOSSerializer

logger = logging.getLogger(__name__)


class SOSViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    @action(detail=False, methods=['post'], url_path='trigger')
    def trigger(self, request):
        """
        POST /sos/trigger/
        Phase 8: Enhanced SOS trigger with push notification broadcasting
        to all family members.
        """
        serializer = TriggerSOSSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        family = request.user.family

        # Create the SOS record
        sos = SOSRecord.objects.create(
            family=family,
            triggered_by=request.user,
            location=serializer.validated_data.get('location'),
            situation=serializer.validated_data.get('situation', ''),
            status=SOSRecord.Status.TRIGGERED,
        )

        # Broadcast high-priority push notification to ALL family members
        notified_ids = []
        try:
            from core.notify import broadcast_family

            user_name = request.user.name or request.user.email
            location_str = ''
            if sos.location:
                loc = sos.location
                if isinstance(loc, dict):
                    location_str = f" (lat: {loc.get('lat', '?')}, lng: {loc.get('lng', '?')})"
                elif isinstance(loc, str):
                    location_str = f" ({loc})"

            notifications = broadcast_family(
                family=family,
                type='sos',
                title='SOS Emergency Alert',
                body=f'{user_name} triggered an SOS!{location_str} {sos.situation or ""}',
                data={
                    'sos_id': str(sos.id),
                    'triggered_by': str(request.user.id),
                    'triggered_by_name': user_name,
                    'location': sos.location,
                    'situation': sos.situation or '',
                    'priority': 'critical',
                },
                exclude_user=request.user,  # Don't notify the triggering user
                push=True,
            )
            notified_ids = [str(n.user_id) for n in notifications]

        except Exception:
            logger.exception('Failed to broadcast SOS notifications for SOS %s', sos.id)

        # Update the SOS record with notified members
        sos.notified_members = notified_ids
        sos.save(update_fields=['notified_members'])

        return success_response(
            data={
                **SOSRecordSerializer(sos).data,
                'notified_count': len(notified_ids),
            },
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['get'], url_path='history')
    def history(self, request):
        """GET /sos/history/ — SOS history for the family."""
        qs = SOSRecord.objects.filter(
            family=request.user.family,
        ).select_related('triggered_by')
        serializer = SOSRecordSerializer(qs, many=True)
        return success_response(data=serializer.data)

    @action(detail=True, methods=['patch'], url_path='resolve')
    def resolve(self, request, pk=None):
        """
        PATCH /sos/<id>/resolve/
        Mark an SOS as resolved and notify family.
        """
        try:
            sos = SOSRecord.objects.get(
                id=pk, family=request.user.family,
            )
        except SOSRecord.DoesNotExist:
            return success_response(
                data={'detail': 'SOS record not found.'},
                status=404,
            )

        if sos.status == SOSRecord.Status.RESOLVED:
            return success_response(
                data={'detail': 'SOS is already resolved.'},
                status=400,
            )

        sos.status = SOSRecord.Status.RESOLVED
        sos.resolved_at = timezone.now()
        sos.save(update_fields=['status', 'resolved_at'])

        # Notify family that SOS has been resolved
        try:
            from apps.notification.tasks import broadcast_family_task
            resolver_name = request.user.name or request.user.email
            broadcast_family_task.delay(
                family_id=str(request.user.family.id),
                type='sos_resolved',
                title='SOS Resolved',
                body=f'The SOS alert has been resolved by {resolver_name}.',
                data={
                    'sos_id': str(sos.id),
                    'resolved_by': str(request.user.id),
                },
            )
        except Exception:
            logger.warning('Failed to send SOS resolved notification', exc_info=True)

        return success_response(data=SOSRecordSerializer(sos).data)
