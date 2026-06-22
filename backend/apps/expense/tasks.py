import logging

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from core.deidentification import get_deidentification_client
from core.storage import build_public_url, delete_object, download_bytes, put_bytes

from .models import Expense

logger = logging.getLogger(__name__)


@shared_task
def redact_receipt_image_task(expense_id):
    try:
        expense = Expense.objects.get(id=expense_id)
        if not expense.raw_image_key or not expense.redacted_image_key:
            raise ValueError('Expense is missing raw or redacted image storage keys.')

        expense.deid_status = Expense.DeidentificationStatus.PROCESSING
        expense.save(update_fields=['deid_status', 'updated_at'])

        raw_bytes = download_bytes(expense.raw_image_key)
        result = get_deidentification_client().redact_image(
            raw_bytes,
            mime_type=_mime_type_from_key(expense.raw_image_key),
        )
        put_bytes(expense.redacted_image_key, result.bytes, result.mime_type)

        expense.image_url = build_public_url(expense.redacted_image_key)
        expense.deid_findings = result.findings_as_dicts()
        expense.deid_status = (
            Expense.DeidentificationStatus.NEEDS_REVIEW
            if result.high_risk
            else Expense.DeidentificationStatus.COMPLETED
        )
        expense.deid_processed_at = timezone.now()
        expense.save()
        return {'status': expense.deid_status, 'expense_id': str(expense.id)}
    except Exception as exc:
        Expense.objects.filter(id=expense_id).update(
            deid_status=Expense.DeidentificationStatus.FAILED,
            deid_findings=[{'error': str(exc)}],
            deid_processed_at=timezone.now(),
        )
        return {'status': Expense.DeidentificationStatus.FAILED, 'error': str(exc)}


@shared_task
def delete_expired_receipt_quarantine_files_task():
    cutoff = timezone.now() - timezone.timedelta(
        hours=getattr(settings, 'DLP_DELETE_RAW_AFTER_HOURS', 24)
    )
    qs = Expense.objects.filter(
        deid_status__in=[
            Expense.DeidentificationStatus.COMPLETED,
            Expense.DeidentificationStatus.NEEDS_REVIEW,
        ],
        deid_processed_at__lt=cutoff,
        raw_image_key__isnull=False,
    ).exclude(raw_image_key='')

    deleted = 0
    errors = 0
    for expense in qs:
        try:
            delete_object(expense.raw_image_key)
        except Exception:
            # A transient storage error (e.g. tunnel 5xx) must not abort the
            # whole sweep; log and keep deleting the remaining files.
            logger.exception(
                'Failed to delete quarantine object %s', expense.raw_image_key
            )
            errors += 1
            continue
        expense.raw_image_key = ''
        expense.save(update_fields=['raw_image_key', 'updated_at'])
        deleted += 1
    return {'deleted': deleted, 'errors': errors}


def _mime_type_from_key(key):
    lowered = key.lower()
    if lowered.endswith('.png'):
        return 'image/png'
    if lowered.endswith('.heic'):
        return 'image/heic'
    return 'image/jpeg'
