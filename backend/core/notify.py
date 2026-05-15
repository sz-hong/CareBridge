"""
Phase 7 — Unified push notification helper.

Usage:
    from core.notify import send_notification, broadcast_family

    # Send to a single user
    send_notification(
        user=user,
        type='health_alert',
        title='Blood Oxygen Low',
        body='Blood oxygen dropped to 90%. Please check.',
        data={'alert_id': str(alert.id)},
    )

    # Broadcast to all family members
    broadcast_family(
        family=family,
        type='sos',
        title='SOS Emergency',
        body='An SOS has been triggered.',
        data={'sos_id': str(sos.id)},
        exclude_user=triggering_user,  # optional
    )
"""
import logging

from django.conf import settings

from core.translation import translate_for_user

logger = logging.getLogger(__name__)


def send_notification(user, type, title, body, data=None, push=True):
    """
    Create a Notification record and optionally send APNs push.

    Args:
        user: User instance to notify.
        type: Notification type string from apps.notification.types.NotificationType.
        title: Notification title.
        body: Notification body text.
        data: Optional dict of extra data.
        push: Whether to also send APNs push (default True).

    Returns:
        Notification instance.
    """
    from apps.notification.models import Notification, Device
    from apps.notification.types import NotificationType

    if type not in NotificationType.values:
        raise ValueError(f'Unsupported notification type: {type}')

    notification = Notification.objects.create(
        user=user,
        type=type,
        title=title,
        title_translated=translate_for_user(
            title,
            user=user,
            mode='mixed_text',
            protected_terms=_notification_protected_terms(user),
        ),
        body=body,
        body_translated=translate_for_user(
            body,
            user=user,
            mode='mixed_text',
            protected_terms=_notification_protected_terms(user),
        ),
        data=data or {},
    )

    if push:
        _send_push_to_user(user, title, body, data)

    return notification


def broadcast_family(family, type, title, body, data=None, exclude_user=None, push=True):
    """
    Send notification to all members of a family.

    Args:
        family: Family instance.
        type: Notification type.
        title: Title.
        body: Body text.
        data: Extra data dict.
        exclude_user: Optional user to exclude (e.g. the one who triggered).
        push: Send APNs push.

    Returns:
        List of created Notification instances.
    """
    from apps.auth_account.models import User

    members = User.objects.filter(family=family, is_active=True)
    if exclude_user:
        members = members.exclude(id=exclude_user.id)

    notifications = []
    for member in members:
        notif = send_notification(
            user=member,
            type=type,
            title=title,
            body=body,
            data=data,
            push=push,
        )
        notifications.append(notif)

    return notifications


def _send_push_to_user(user, title, body, data=None):
    """Send APNs push notification to all active devices of a user."""
    import os

    from apps.notification.models import Device

    # Skip silently when APNs isn't truly set up. The env file ships with a
    # placeholder path like `/path/to/AuthKey.p8`, so a non-empty string
    # alone isn't enough — verify the .p8 file actually exists on disk.
    apns_key = getattr(settings, 'APNS_AUTH_KEY_PATH', '')
    if not apns_key or not os.path.isfile(apns_key):
        logger.debug('APNs not configured, skipping push for user %s', user.id)
        return

    devices = Device.objects.filter(user=user, is_active=True)
    if not devices.exists():
        logger.debug('No active devices for user %s', user.id)
        return

    try:
        from core.apns import send_push

        for device in devices:
            try:
                send_push(
                    device_token=device.device_token,
                    title=title,
                    body=body,
                    data=data,
                )
            except Exception:
                logger.warning(
                    'Failed to push to device %s for user %s',
                    device.id, user.id,
                    exc_info=True,
                )
    except ImportError:
        logger.warning('apns2 not installed, skipping push notifications')
    except Exception:
        logger.exception('Push notification error for user %s', user.id)


def _notification_protected_terms(user):
    family = getattr(user, 'family', None)
    terms = [
        getattr(user, 'name', None),
        getattr(family, 'name', None),
        getattr(family, 'elder_name', None),
    ]
    return [term for term in terms if term]
