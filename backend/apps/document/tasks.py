import io
import logging

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from core.deidentification import get_deidentification_client
from core.storage import build_public_url, delete_object, download_bytes, put_bytes
from core.upload_paths import processed_key_for_raw_key

from .models import Document

logger = logging.getLogger(__name__)


# PDF pages are rasterized at this DPI before per-page DLP image redaction.
# 150 keeps text legible while keeping each page image well within the DLP
# image inspection size limit.
PDF_RASTER_DPI = 150

# Cap each rasterized page's width so an oversized page cannot exceed the DLP
# image size limit; height is scaled proportionally to preserve aspect ratio.
PDF_PAGE_MAX_WIDTH = 2000


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
        document.redacted_file_key = processed_key_for_raw_key(
            document.raw_file_key,
            content_type=result_mime_type,
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
    # NEEDS_REVIEW is intentionally excluded: its raw quarantine file must be
    # retained until a human approves the document (which flips it to COMPLETED).
    qs = Document.objects.filter(
        deid_status=Document.DeidentificationStatus.COMPLETED,
        deid_processed_at__lt=cutoff,
        raw_file_key__isnull=False,
    ).exclude(raw_file_key='')

    deleted = 0
    errors = 0
    for document in qs:
        try:
            delete_object(document.raw_file_key)
        except Exception:
            # A transient storage error (e.g. tunnel 5xx) must not abort the
            # whole sweep; log and keep deleting the remaining files.
            logger.exception(
                'Failed to delete quarantine object %s', document.raw_file_key
            )
            errors += 1
            continue
        document.raw_file_key = ''
        document.save(update_fields=['raw_file_key'])
        deleted += 1
    return {'deleted': deleted, 'errors': errors}


def _detect_mime_type(raw_bytes, declared_mime):
    """Sniff the real content type from magic bytes.

    Clients sometimes upload images/PDFs as ``application/octet-stream``; trusting
    that would route an image to text de-identification (which then fails on the
    DLP content-size limit). The byte signature is authoritative; the declared
    mime is only a fallback.
    """
    header = raw_bytes[:16]
    if header.startswith(b'%PDF'):
        return 'application/pdf'
    if header.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if header.startswith(b'\xff\xd8\xff'):
        return 'image/jpeg'
    if header.startswith((b'GIF87a', b'GIF89a')):
        return 'image/gif'
    if header.startswith(b'BM'):
        return 'image/bmp'
    if header[:4] == b'RIFF' and raw_bytes[8:12] == b'WEBP':
        return 'image/webp'
    if raw_bytes[4:8] == b'ftyp' and raw_bytes[8:12] in (
        b'heic', b'heix', b'mif1', b'heif',
    ):
        return 'image/heic'
    declared = (declared_mime or '').lower()
    if declared and declared != 'application/octet-stream':
        return declared
    return 'application/octet-stream'


def _redact_document_bytes(raw_bytes, mime_type):
    client = get_deidentification_client()
    mime_type = _detect_mime_type(raw_bytes, mime_type)
    if mime_type == 'application/pdf':
        return _redact_pdf_bytes(client, raw_bytes)

    if mime_type.startswith('image/'):
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


def _redact_pdf_bytes(client, raw_bytes):
    """Rasterize every PDF page, redact each via DLP image redaction, then
    stitch the redacted pages into a single tall PNG.

    DLP's content API cannot redact a PDF and return a redacted PDF, so we turn
    each page into an image (which DLP *can* redact) and combine them. The
    output is a single ``image/png`` so it shares the same preview path as
    image documents and receipts.
    """
    page_images = _rasterize_pdf_to_images(raw_bytes)
    if not page_images:
        raise ValueError('PDF produced no rasterizable pages.')

    redacted_pages = []
    findings = []
    high_risk = False
    for page_png in page_images:
        redacted = client.redact_image(page_png, mime_type='image/png')
        redacted_pages.append(redacted.bytes)
        findings.extend(redacted.findings_as_dicts())
        high_risk = high_risk or redacted.high_risk

    stitched = _stitch_images_vertically(redacted_pages)
    return (stitched, 'image/png', findings, high_risk)


def _rasterize_pdf_to_images(raw_bytes):
    """Render each PDF page to PNG bytes via pdf2image (poppler).

    Returns a list of PNG byte strings, one per page. Oversized pages are
    downscaled to ``PDF_PAGE_MAX_WIDTH`` so a single page cannot exceed the DLP
    image size limit.
    """
    from pdf2image import convert_from_bytes

    pages = convert_from_bytes(raw_bytes, dpi=PDF_RASTER_DPI, fmt='png')
    page_png_list = []
    for page in pages:
        if page.width > PDF_PAGE_MAX_WIDTH:
            ratio = PDF_PAGE_MAX_WIDTH / page.width
            page = page.resize(
                (PDF_PAGE_MAX_WIDTH, max(1, round(page.height * ratio)))
            )
        buffer = io.BytesIO()
        page.save(buffer, format='PNG')
        page_png_list.append(buffer.getvalue())
    return page_png_list


def _stitch_images_vertically(page_png_list):
    """Combine page PNGs into one tall PNG (white background, top-aligned)."""
    from PIL import Image

    images = [Image.open(io.BytesIO(data)).convert('RGB') for data in page_png_list]
    try:
        if len(images) == 1:
            buffer = io.BytesIO()
            images[0].save(buffer, format='PNG')
            return buffer.getvalue()

        total_width = max(image.width for image in images)
        total_height = sum(image.height for image in images)
        canvas = Image.new('RGB', (total_width, total_height), (255, 255, 255))
        offset_y = 0
        for image in images:
            canvas.paste(image, (0, offset_y))
            offset_y += image.height
        buffer = io.BytesIO()
        canvas.save(buffer, format='PNG')
        return buffer.getvalue()
    finally:
        for image in images:
            image.close()
