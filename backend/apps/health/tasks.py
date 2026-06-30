import logging

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from apps.notification.models import Notification
from apps.notification.types import NotificationType

from .models import HealthAlert, HealthData

logger = logging.getLogger(__name__)


@shared_task
def delete_expired_health_data_task():
    retention_days = getattr(settings, 'HEALTH_DATA_RETENTION_DAYS', 90)
    cutoff = timezone.now() - timezone.timedelta(days=retention_days)

    expired_alert_ids = list(
        HealthAlert.objects.filter(recorded_at__lt=cutoff)
        .values_list('id', flat=True)
    )
    expired_alert_id_strings = [str(alert_id) for alert_id in expired_alert_ids]

    notifications_deleted = 0
    if expired_alert_id_strings:
        notifications_deleted, _ = Notification.objects.filter(
            type=NotificationType.HEALTH_ALERT,
            data__alert_id__in=expired_alert_id_strings,
        ).delete()

    health_alerts_deleted = 0
    if expired_alert_ids:
        health_alerts_deleted, _ = HealthAlert.objects.filter(
            id__in=expired_alert_ids,
        ).delete()

    health_data_deleted, _ = HealthData.objects.filter(
        recorded_at__lt=cutoff,
    ).delete()

    result = {
        'health_data_deleted': health_data_deleted,
        'health_alerts_deleted': health_alerts_deleted,
        'notifications_deleted': notifications_deleted,
    }
    if any(result.values()):
        logger.info(
            'Deleted expired health records before %s: %s',
            cutoff,
            result,
        )
    return result
