from celery import shared_task
from django.conf import settings
from django.utils import timezone

from core.deidentification import get_deidentification_client
from core.storage import build_public_url, delete_object, download_bytes, put_bytes

from .models import Document


@shared_task
def deidentify_document_task(document_id):
    try:
        document = Document.objects.get(id=document_id)
        if not document.raw_file_key or not document.redacted_file_key:
            raise ValueError('Document is missing raw or redacted storage keys.')

        document.deid_status = Document.DeidentificationStatus.PROCESSING
        document.save(update_fields=['deid_status'])

        raw_bytes = download_bytes(document.raw_file_key)
        result_bytes, result_mime_type, findings, high_risk = _redact_document_bytes(
            raw_bytes,
            document.mime_type,
        )
        put_bytes(document.redacted_file_key, result_bytes, result_mime_type)

        document.file_url = build_public_url(document.redacted_file_key)
        document.deid_findings = findings
        document.deid_status = (
            Document.DeidentificationStatus.NEEDS_REVIEW
            if high_risk
            else Document.DeidentificationStatus.COMPLETED
        )
        document.deid_processed_at = timezone.now()
        document.save()
        return {'status': document.deid_status, 'document_id': str(document.id)}
    except Exception as exc:
        Document.objects.filter(id=document_id).update(
            deid_status=Document.DeidentificationStatus.FAILED,
            deid_findings=[{'error': str(exc)}],
            deid_processed_at=timezone.now(),
        )
        return {'status': Document.DeidentificationStatus.FAILED, 'error': str(exc)}


@shared_task
def delete_expired_document_quarantine_files_task():
    cutoff = timezone.now() - timezone.timedelta(
        hours=getattr(settings, 'DLP_DELETE_RAW_AFTER_HOURS', 24)
    )
    qs = Document.objects.filter(
        deid_status=Document.DeidentificationStatus.COMPLETED,
        deid_processed_at__lt=cutoff,
        raw_file_key__isnull=False,
    ).exclude(raw_file_key='')

    deleted = 0
    for document in qs:
        delete_object(document.raw_file_key)
        document.raw_file_key = ''
        document.save(update_fields=['raw_file_key'])
        deleted += 1
    return {'deleted': deleted}


def _redact_document_bytes(raw_bytes, mime_type):
    client = get_deidentification_client()
    if mime_type.startswith('image/') or mime_type == 'application/pdf':
        redacted = client.redact_image(raw_bytes, mime_type=mime_type)
        return (
            redacted.bytes,
            redacted.mime_type,
            redacted.findings_as_dicts(),
            redacted.high_risk,
        )

    try:
        raw_text = raw_bytes.decode('utf-8')
    except UnicodeDecodeError:
        raw_text = raw_bytes.decode('utf-8', errors='ignore')
    result = client.deidentify_text(raw_text)
    return (
        result.text.encode('utf-8'),
        'text/plain',
        result.findings_as_dicts(),
        result.high_risk,
    )
