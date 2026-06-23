"""
Phase 7 — Celery tasks for asynchronous push notification delivery.

These tasks are designed to be called from Django views/signals so that
the HTTP response is not blocked by slow APNs calls.
"""
import logging

from celery import shared_task

from apps.notification.types import NotificationType

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def send_notification_task(self, user_id, type, title, body, data=None):
    """
    Async task: create Notification record + send APNs push to a single user.
    """
    try:
        from apps.auth_account.models import User
        from core.notify import send_notification

        user = User.objects.get(id=user_id)
        send_notification(
            user=user,
            type=type,
            title=title,
            body=body,
            data=data,
            push=True,
        )
    except Exception as exc:
        logger.exception('send_notification_task failed for user %s', user_id)
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def broadcast_family_task(self, family_id, type, title, body, data=None, exclude_user_id=None):
    """
    Async task: send notification to all members of a family.
    """
    try:
        from apps.family.models import Family
        from apps.auth_account.models import User
        from core.notify import broadcast_family

        family = Family.objects.get(id=family_id)
        exclude_user = None
        if exclude_user_id:
            exclude_user = User.objects.get(id=exclude_user_id)

        broadcast_family(
            family=family,
            type=type,
            title=title,
            body=body,
            data=data,
            exclude_user=exclude_user,
            push=True,
        )
    except Exception as exc:
        logger.exception('broadcast_family_task failed for family %s', family_id)
        raise self.retry(exc=exc)


@shared_task
def send_medication_reminders():
    """
    Periodic task: check for upcoming medication times and send reminders.
    Should be scheduled in Celery Beat (e.g. every 15 minutes).
    """
    from django.utils import timezone
    from apps.medication.models import Medication
    from apps.auth_account.models import User
    from core.notify import broadcast_family

    now = timezone.localtime()
    current_time = now.strftime('%H:%M')

    # Find medications with reminders enabled and a time matching the current window.
    active_meds = Medication.objects.filter(is_active=True, reminder_enabled=True)

    for med in active_meds:
        if not med.times:
            continue
        for slot in med.times:
            # Check if the scheduled time falls within ±7 min of now
            if _time_within_window(slot, current_time, window_minutes=7):
                broadcast_family(
                    family=med.family,
                    type=NotificationType.MEDICATION_REMINDER,
                    title=f'Medication Reminder: {med.name}',
                    body=f'Time to take {med.name} ({med.dosage})',
                    data={
                        'medication_id': str(med.id),
                        'scheduled_time': slot,
                    },
                    push=True,
                )
                logger.info(
                    'Sent medication reminder for %s (family %s)',
                    med.name, med.family_id,
                )


READ_NOTIFICATION_RETENTION_DAYS = 7


@shared_task
def delete_read_notifications_task():
    """Periodic task: delete notifications that have been read for over a week.

    Keeps the notification center tidy without asking users to delete
    manually, which would otherwise hit role-based delete permissions
    (caregivers cannot delete). Unread notifications are always kept.
    Should be scheduled in Celery Beat (e.g. once a day).
    """
    from datetime import timedelta
    from django.utils import timezone
    from apps.notification.models import Notification

    cutoff = timezone.now() - timedelta(days=READ_NOTIFICATION_RETENTION_DAYS)
    deleted, _ = Notification.objects.filter(
        is_read=True, read_at__lt=cutoff,
    ).delete()
    if deleted:
        logger.info(
            'Deleted %s read notifications read before %s', deleted, cutoff,
        )
    return deleted


def _time_within_window(slot_time_str, current_time_str, window_minutes=7):
    """Check if slot_time is within window_minutes of current_time."""
    try:
        from datetime import datetime, timedelta

        slot = datetime.strptime(slot_time_str, '%H:%M')
        current = datetime.strptime(current_time_str, '%H:%M')

        diff = abs((slot - current).total_seconds())
        return diff <= window_minutes * 60
    except (ValueError, TypeError):
        return False
