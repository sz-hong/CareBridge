from datetime import timedelta
from decimal import Decimal

from django.db.models import Avg, Sum
from django.db.models.functions import TruncDay, TruncHour
from django.utils import timezone
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ViewSet

from core.responses import success_response
from .models import HealthData, HealthAlert, HealthAlertThreshold
from .serializers import (
    HealthDataSerializer,
    SyncHealthDataSerializer,
    HealthAlertSerializer,
    HealthAlertThresholdSerializer,
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
                type='health_alert',
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


class HealthDataViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        """GET /health-data/ with optional filters: type, date_from, date_to, aggregation."""
        family = request.user.family
        qs = HealthData.objects.filter(family=family)

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
        """POST /health-data/sync/ — batch sync health data points."""
        family = request.user.family
        serializer = SyncHealthDataSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        items = serializer.validated_data['data']
        created_count = 0
        alerts = []

        for item in items:
            obj, created = HealthData.objects.get_or_create(
                family=family,
                type=item['type'],
                recorded_at=item['recorded_at'],
                defaults={
                    'value': item['value'],
                    'unit': item['unit'],
                    'device_id': item.get('device_id', ''),
                },
            )
            if created:
                created_count += 1
                alert = _check_thresholds(family, obj)
                if alert:
                    alerts.append(HealthAlertSerializer(alert).data)

        data = {
            'synced': created_count,
            'duplicates': len(items) - created_count,
            'alerts': alerts,
        }
        return success_response(data=data, status=201)

    @action(detail=False, methods=['get'], url_path='dashboard')
    def dashboard(self, request):
        """GET /health-data/dashboard/ — latest value for each health type."""
        family = request.user.family
        latest = {}
        for type_choice in HealthData.Type.values:
            entry = (
                HealthData.objects
                .filter(family=family, type=type_choice)
                .order_by('-recorded_at')
                .first()
            )
            if entry:
                latest[type_choice] = HealthDataSerializer(entry).data

        return success_response(data=latest)

    @action(detail=False, methods=['get'], url_path='alerts')
    def alerts(self, request):
        """GET /health-data/alerts/ — list alerts for the family."""
        family = request.user.family
        qs = HealthAlert.objects.filter(family=family).order_by('-created_at')
        serializer = HealthAlertSerializer(qs[:100], many=True)
        return success_response(data=serializer.data)

    @action(
        detail=False,
        methods=['put'],
        url_path=r'alerts/(?P<alert_id>[^/.]+)/acknowledge',
    )
    def acknowledge_alert(self, request, alert_id=None):
        """PUT /health-data/alerts/<id>/acknowledge/"""
        family = request.user.family
        try:
            alert = HealthAlert.objects.get(id=alert_id, family=family)
        except HealthAlert.DoesNotExist:
            return success_response(data={'detail': 'Alert not found.'}, status=404)

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
        family = request.user.family
        today = timezone.now().date()
        seven_days_ago = today - timedelta(days=6)

        results = (
            HealthData.objects.filter(
                family=family,
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
        steps_by_day = {r['day'].date(): float(r['total_steps']) for r in results}

        # Build array for all 7 days
        data = []
        for i in range(7):
            d = seven_days_ago + timedelta(days=i)
            data.append({
                'date': d.isoformat(),
                'total_steps': steps_by_day.get(d, 0),
            })

        return success_response(data=data)
