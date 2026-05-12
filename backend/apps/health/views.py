from datetime import timedelta
from decimal import Decimal

from django.db.models import Avg, Sum
from django.db.models.functions import TruncDay, TruncHour
from django.utils import timezone
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ViewSet

from core.permissions import CaregiverCannotDelete
from core.responses import error_response, success_response
from core.viewsets import FamilyScopedQuerySetMixin
from apps.notification.types import NotificationType
from .models import HealthData, HealthAlert, HealthAlertThreshold
from .serializers import (
    HealthDataSerializer,
    SyncHealthDataSerializer,
    HealthAlertSerializer,
    HealthAlertThresholdSerializer,
)


def _broadcast_health_update(family, points, alerts):
    """Push new health data points + alerts to ws/health/ family group.

    msgpack (the channel layer's packer) can't serialize UUID/datetime,
    so we round-trip through json with default=str — same workaround the
    chat consumer uses.
    """
    import json

    from asgiref.sync import async_to_sync
    from channels.layers import get_channel_layer

    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

    payload = json.loads(json.dumps({
        'type':   'health.update',
        'points': points,
        'alerts': alerts,
    }, default=str))

    async_to_sync(channel_layer.group_send)(
        f'health_{family.id}',
        {'type': 'health_update', 'payload': payload},
    )


def _check_thresholds(family, data_point):
    """Check a single health data point against family thresholds and create alert if abnormal."""
    try:
        threshold = HealthAlertThreshold.objects.get(family=family)
    except HealthAlertThreshold.DoesNotExist:
        return None

    severity = None
    threshold_value = None
    value = data_point.value

    if data_point.type == HealthData.Type.HEART_RATE:
        if value > threshold.heart_rate_high:
            severity = HealthAlert.Severity.WARNING
            threshold_value = Decimal(threshold.heart_rate_high)
        elif value < threshold.heart_rate_low:
            severity = HealthAlert.Severity.WARNING
            threshold_value = Decimal(threshold.heart_rate_low)
    elif data_point.type == HealthData.Type.BLOOD_OXYGEN:
        if value < threshold.blood_oxygen_low:
            severity = HealthAlert.Severity.CRITICAL
            threshold_value = threshold.blood_oxygen_low

    if severity and threshold_value is not None:
        alert = HealthAlert.objects.create(
            family=family,
            type=data_point.type,
            value=value,
            threshold=threshold_value,
            severity=severity,
            recorded_at=data_point.recorded_at,
        )

        # Phase 7: Send push notification to family members
        try:
            from apps.notification.tasks import broadcast_family_task
            severity_label = 'Critical' if severity == HealthAlert.Severity.CRITICAL else 'Warning'
            broadcast_family_task.delay(
                family_id=str(family.id),
                type=NotificationType.HEALTH_ALERT,
                title=f'Health Alert: {data_point.get_type_display()} ({severity_label})',
                body=f'{data_point.get_type_display()} value {float(value)} is abnormal (threshold: {float(threshold_value)}).',
                data={
                    'alert_id': str(alert.id),
                    'health_type': data_point.type,
                    'severity': severity,
                },
            )
        except Exception:
            import logging
            logging.getLogger(__name__).warning(
                'Failed to send health alert notification', exc_info=True
            )

        return alert
    return None


class HealthDataViewSet(FamilyScopedQuerySetMixin, ViewSet):
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def list(self, request):
        """GET /health-data/ with optional filters: type, date_from, date_to, aggregation."""
        qs = self.scope_queryset_to_family(HealthData.objects.all())

        data_type = request.query_params.get('type')
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')
        aggregation = request.query_params.get('aggregation')  # raw, hourly, daily

        if data_type:
            qs = qs.filter(type=data_type)
        if date_from:
            qs = qs.filter(recorded_at__date__gte=date_from)
        if date_to:
            qs = qs.filter(recorded_at__date__lte=date_to)

        if aggregation == 'hourly':
            results = (
                qs.annotate(period=TruncHour('recorded_at'))
                .values('type', 'period')
                .annotate(avg_value=Avg('value'))
                .order_by('type', 'period')
            )
            data = [
                {
                    'type': r['type'],
                    'period': r['period'].isoformat(),
                    'avg_value': float(r['avg_value']),
                }
                for r in results
            ]
            return success_response(data=data)

        if aggregation == 'daily':
            results = (
                qs.annotate(period=TruncDay('recorded_at'))
                .values('type', 'period')
                .annotate(avg_value=Avg('value'))
                .order_by('type', 'period')
            )
            data = [
                {
                    'type': r['type'],
                    'period': r['period'].isoformat(),
                    'avg_value': float(r['avg_value']),
                }
                for r in results
            ]
            return success_response(data=data)

        # Default: raw data
        serializer = HealthDataSerializer(qs[:200], many=True)
        return success_response(data=serializer.data)

    @action(detail=False, methods=['post'], url_path='sync')
    def sync(self, request):
        """POST /health-data/sync/ — batch sync health data points.

        Idempotent via the (family, type, recorded_at) unique constraint:
        re-uploading the same samples is a no-op. Reports back how many
        rows were actually inserted vs. duplicates so the client can
        advance its anchor confidently.
        """
        family = request.user.family
        if family is None:
            return error_response(
                code='no_family',
                message='User is not in a family.',
                status=400,
            )

        # 健康同步綁定：只有目前綁定的 user 可以推資料。沒人綁定時，第一個
        # 上傳者要先打 /families/me/health-binding/ 把自己 claim 起來。
        # 這層強制要在後端，否則 FE 的 UI 鎖只是裝飾。
        bound_user = family.health_binding_user
        if bound_user is None:
            return error_response(
                code='health_binding_required',
                message='No device is currently bound for health sync. Claim the binding first.',
                status=403,
            )
        if bound_user.id != request.user.id:
            return error_response(
                code='health_binding_not_owner',
                message='Another device in this family is the current health-sync owner.',
                status=403,
            )

        serializer = SyncHealthDataSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        items = serializer.validated_data['data']
        created_count = 0
        alerts = []
        broadcast_points = []

        for item in items:
            obj, created = HealthData.objects.get_or_create(
                family=family,
                type=item['type'],
                recorded_at=item['recorded_at'],
                defaults={
                    'value': item['value'],
                    'unit': item['unit'],
                    'device_id': item.get('device_id', ''),
                    'source': item.get('source', HealthData.Source.OTHER),
                },
            )
            if created:
                created_count += 1
                broadcast_points.append(HealthDataSerializer(obj).data)
                alert = _check_thresholds(family, obj)
                if alert:
                    alerts.append(HealthAlertSerializer(alert).data)

        # Realtime fan-out — push the new samples + any triggered alerts to
        # every family member connected to ws/health/. Skipped on duplicates
        # so the dashboard doesn't replay stale data on retries.
        if broadcast_points or alerts:
            try:
                _broadcast_health_update(
                    family,
                    points=broadcast_points,
                    alerts=alerts,
                )
            except Exception:
                import logging
                logging.getLogger(__name__).warning(
                    'Failed to broadcast health update', exc_info=True,
                )

        data = {
            'synced': created_count,
            'duplicates': len(items) - created_count,
            'alerts': alerts,
        }
        return success_response(data=data, status=201)

    @action(detail=False, methods=['get'], url_path='dashboard')
    def dashboard(self, request):
        """GET /health-data/dashboard/ — latest value for each health type."""
        latest = {}
        for type_choice in HealthData.Type.values:
            entry = (
                self.scope_queryset_to_family(HealthData.objects.all())
                .filter(type=type_choice)
                .order_by('-recorded_at')
                .first()
            )
            if entry:
                latest[type_choice] = HealthDataSerializer(entry).data

        return success_response(data=latest)

    @action(detail=False, methods=['get'], url_path='alerts')
    def alerts(self, request):
        """GET /health-data/alerts/ — list alerts for the family."""
        qs = self.scope_queryset_to_family(HealthAlert.objects.all()).order_by('-created_at')
        serializer = HealthAlertSerializer(qs[:100], many=True)
        return success_response(data=serializer.data)

    @action(
        detail=False,
        methods=['put'],
        url_path=r'alerts/(?P<alert_id>[^/.]+)/acknowledge',
    )
    def acknowledge_alert(self, request, alert_id=None):
        """PUT /health-data/alerts/<id>/acknowledge/"""
        qs = self.scope_queryset_to_family(HealthAlert.objects.all())
        try:
            alert = qs.get(id=alert_id)
        except HealthAlert.DoesNotExist:
            return error_response(
                code='not_found',
                message='Alert not found.',
                status=404,
            )

        alert.acknowledged_by = request.user
        alert.acknowledged_at = timezone.now()
        alert.save(update_fields=['acknowledged_by', 'acknowledged_at'])

        serializer = HealthAlertSerializer(alert)
        return success_response(data=serializer.data)

    @action(detail=False, methods=['get', 'put'], url_path='thresholds')
    def thresholds(self, request):
        """GET/PUT /health-data/thresholds/"""
        family = request.user.family

        if request.method == 'GET':
            threshold, _ = HealthAlertThreshold.objects.get_or_create(
                family=family,
                defaults={'updated_by': request.user},
            )
            serializer = HealthAlertThresholdSerializer(threshold)
            return success_response(data=serializer.data)

        # PUT
        threshold, _ = HealthAlertThreshold.objects.get_or_create(
            family=family,
            defaults={'updated_by': request.user},
        )
        serializer = HealthAlertThresholdSerializer(
            threshold, data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save(updated_by=request.user)
        return success_response(data=serializer.data)

    @action(detail=False, methods=['get'], url_path='weekly-steps')
    def weekly_steps(self, request):
        """GET /health-data/weekly-steps/ — array of 7 daily step totals."""
        today = timezone.localdate()
        seven_days_ago = today - timedelta(days=6)

        results = (
            self.scope_queryset_to_family(HealthData.objects.all()).filter(
                type=HealthData.Type.STEP_COUNT,
                recorded_at__date__gte=seven_days_ago,
                recorded_at__date__lte=today,
            )
            .annotate(day=TruncDay('recorded_at'))
            .values('day')
            .annotate(total_steps=Sum('value'))
            .order_by('day')
        )

        # Build a dict of date -> total
        steps_by_day = {r['day'].date(): int(r['total_steps'] or 0) for r in results}

        # Return 7-element int array, oldest → newest
        data = [
            steps_by_day.get(seven_days_ago + timedelta(days=i), 0)
            for i in range(7)
        ]
        return success_response(data=data)
