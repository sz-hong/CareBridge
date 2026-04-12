import logging

from apns2.client import APNsClient, NotificationPriority
from apns2.payload import Payload
from django.conf import settings

logger = logging.getLogger(__name__)


def _get_apns_client():
    """
    Create and return an APNs client using settings from Django settings.

    Expected settings:
        APNS_KEY_FILE: Path to the .p8 authentication key file.
        APNS_KEY_ID: The 10-character Key ID.
        APNS_TEAM_ID: The 10-character Team ID.
        APNS_TOPIC: The bundle ID of the app (e.g. 'com.example.carebridge').
        APNS_USE_SANDBOX: Boolean, whether to use sandbox environment (default True).
    """
    key_file = getattr(settings, 'APNS_KEY_FILE', None)
    key_id = getattr(settings, 'APNS_KEY_ID', None)
    team_id = getattr(settings, 'APNS_TEAM_ID', None)
    use_sandbox = getattr(settings, 'APNS_USE_SANDBOX', True)

    if not all([key_file, key_id, team_id]):
        raise RuntimeError(
            'APNs is not properly configured. '
            'Ensure APNS_KEY_FILE, APNS_KEY_ID, and APNS_TEAM_ID are set in Django settings.'
        )

    from apns2.credentials import TokenCredentials

    token_credentials = TokenCredentials(
        auth_key_path=key_file,
        auth_key_id=key_id,
        team_id=team_id,
    )

    client = APNsClient(
        credentials=token_credentials,
        use_sandbox=use_sandbox,
    )

    return client


def send_push(device_token, title, body, data=None, badge=None):
    """
    Send an APNs push notification to a single device.

    Args:
        device_token (str): The device's APNs token.
        title (str): The notification title.
        body (str): The notification body text.
        data (dict, optional): Custom data payload to include.
        badge (int, optional): Badge count to display on the app icon.

    Returns:
        bool: True if the notification was sent successfully.

    Raises:
        RuntimeError: If APNs settings are not configured.
        Exception: If the APNs service returns an error.
    """
    topic = getattr(settings, 'APNS_TOPIC', None)
    if not topic:
        raise RuntimeError('APNS_TOPIC is not configured in Django settings.')

    payload = Payload(
        alert={'title': title, 'body': body},
        badge=badge,
        custom=data or {},
    )

    client = _get_apns_client()

    try:
        from apns2.client import Notification

        notification = Notification(
            token=device_token,
            payload=payload,
            priority=NotificationPriority.Immediate,
            topic=topic,
        )

        response = client.send_notification_batch(
            notifications=[notification],
            topic=topic,
        )

        # send_notification_batch returns a dict of token -> response
        if device_token in response:
            result = response[device_token]
            if result == 'Success':
                logger.info('Push notification sent to %s', device_token[:8])
                return True
            else:
                logger.error(
                    'APNs error for token %s: %s', device_token[:8], result
                )
                raise Exception(f'APNs delivery failed: {result}')

        logger.info('Push notification sent to %s', device_token[:8])
        return True

    except Exception:
        logger.exception('Failed to send push notification to %s', device_token[:8])
        raise
