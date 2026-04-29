import asyncio
import logging

from django.conf import settings

logger = logging.getLogger(__name__)


async def _send_push_async(device_token, title, body, data=None, badge=None):
    """
    Send an APNs push notification using aioapns (async, h2-based).

    Expected Django settings:
        APNS_KEY_FILE   – Path to the .p8 authentication key file.
        APNS_KEY_ID     – 10-character Key ID.
        APNS_TEAM_ID    – 10-character Team ID.
        APNS_TOPIC      – Bundle ID (e.g. 'com.example.carebridge').
        APNS_USE_SANDBOX – Boolean (default True).
    """
    from aioapns import APNs, NotificationRequest

    # Settings.py exposes the path under APNS_AUTH_KEY_PATH; accept the
    # legacy APNS_KEY_FILE name too so older configs keep working.
    key_file = (
        getattr(settings, 'APNS_AUTH_KEY_PATH', None)
        or getattr(settings, 'APNS_KEY_FILE', None)
    )
    key_id = getattr(settings, 'APNS_KEY_ID', None)
    team_id = getattr(settings, 'APNS_TEAM_ID', None)
    topic = getattr(settings, 'APNS_TOPIC', None)
    use_sandbox = getattr(settings, 'APNS_USE_SANDBOX', True)

    if not all([key_file, key_id, team_id, topic]):
        raise RuntimeError(
            'APNs is not properly configured. '
            'Ensure APNS_AUTH_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, '
            'and APNS_TOPIC are set in Django settings.'
        )

    apns = APNs(
        key=key_file,
        key_id=key_id,
        team_id=team_id,
        topic=topic,
        use_sandbox=use_sandbox,
    )

    # Build the APS payload
    alert = {'title': title, 'body': body}
    message = {'aps': {'alert': alert}}
    if badge is not None:
        message['aps']['badge'] = badge
    if data:
        message.update(data)

    request = NotificationRequest(
        device_token=device_token,
        message=message,
    )

    response = await apns.send_notification(request)
    if not response.is_successful:
        logger.error(
            'APNs error for token %s: %s (%s)',
            device_token[:8], response.description, response.status,
        )
        raise Exception(f'APNs delivery failed: {response.description}')

    logger.info('Push notification sent to %s', device_token[:8])
    return True


def send_push(device_token, title, body, data=None, badge=None):
    """
    Synchronous wrapper – safe to call from Django views and Celery tasks.

    Args:
        device_token (str): The device's APNs token.
        title (str): The notification title.
        body (str): The notification body text.
        data (dict, optional): Custom data payload to include.
        badge (int, optional): Badge count to display on the app icon.

    Returns:
        bool: True if the notification was sent successfully.
    """
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if loop and loop.is_running():
        # Inside an existing async context (e.g. Channels, ASGI) – schedule it
        future = asyncio.ensure_future(
            _send_push_async(device_token, title, body, data, badge)
        )
        return future  # caller can await if needed
    else:
        return asyncio.run(
            _send_push_async(device_token, title, body, data, badge)
        )
