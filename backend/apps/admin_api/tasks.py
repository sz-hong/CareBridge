import logging
from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from .models import AdminMutationAuditLog, AdminRequestLog

logger = logging.getLogger(__name__)


def retention_days(setting_name, default):
    value = getattr(settings, setting_name, default)
    try:
        return max(1, int(value))
    except (TypeError, ValueError):
        return default


def cleanup_expired_admin_logs():
    request_days = retention_days('ADMIN_REQUEST_LOG_RETENTION_DAYS', 14)
    audit_days = retention_days('ADMIN_AUDIT_LOG_RETENTION_DAYS', 180)
    now = timezone.now()

    request_deleted, _ = AdminRequestLog.objects.filter(
        created_at__lt=now - timedelta(days=request_days),
    ).delete()
    audit_deleted, _ = AdminMutationAuditLog.objects.filter(
        created_at__lt=now - timedelta(days=audit_days),
    ).delete()

    return {
        'request_log_retention_days': request_days,
        'audit_log_retention_days': audit_days,
        'request_logs_deleted': request_deleted,
        'audit_logs_deleted': audit_deleted,
    }


@shared_task
def delete_expired_admin_logs_task():
    """Delete old dashboard request and mutation audit log rows daily."""
    result = cleanup_expired_admin_logs()
    if result['request_logs_deleted'] or result['audit_logs_deleted']:
        logger.info(
            'Deleted %(request_logs_deleted)s request log(s) older than '
            '%(request_log_retention_days)s day(s) and %(audit_logs_deleted)s '
            'audit log(s) older than %(audit_log_retention_days)s day(s).',
            result,
        )
    return result