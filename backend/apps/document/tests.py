from django.conf import settings
from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from unittest.mock import patch
from rest_framework.test import APIClient

from core.deidentification import DeidentificationResult, PIIFinding, RedactedFile
from apps.auth_account.models import User
from apps.document.models import Document
from apps.document.tasks import (
    deidentify_document_task,
    delete_expired_document_quarantine_files_task,
)
from apps.family.models import Family


def _png_bytes(color, size=(10, 10)):
    """Return real PNG bytes so the rasterize/stitch path can be exercised."""
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new('RGB', size, color).save(buffer, format='PNG')
    return buffer.getvalue()


class DocumentCeleryScheduleTests(SimpleTestCase):
    def test_document_and_receipt_quarantine_cleanup_are_scheduled_hourly(self):
        schedule = settings.CELERY_BEAT_SCHEDULE

        document_cleanup = schedule['delete-expired-document-quarantine-files-hourly']
        receipt_cleanup = schedule['delete-expired-receipt-quarantine-files-hourly']

        self.assertEqual(
            document_cleanup['task'],
            'apps.document.tasks.delete_expired_document_quarantine_files_task',
        )
        self.assertEqual(
            receipt_cleanup['task'],
            'apps.expense.tasks.delete_expired_receipt_quarantine_files_task',
        )
        self.assertEqual(document_cleanup['schedule'], 3600.0)
        self.assertEqual(receipt_cleanup['schedule'], 3600.0)


class DocumentAPIContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='docs@example.com',
            password='password123',
            name='Docs User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Docs Family',
            elder_name='Elder',
            invite_code='444444',
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.caregiver = User.objects.create_user(
            email='caregiver-docs@example.com',
            password='password123',
            name='Docs Caregiver',
            role=User.Role.CAREGIVER,
            family=self.family,
        )
        self.client.force_authenticate(self.user)

    def test_delete_returns_success_envelope_that_mobile_can_decode(self):
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Insurance',
            category=Document.Category.INSURANCE,
            file_url='https://example.com/doc.pdf',
            file_size=128,
            mime_type='application/pdf',
        )

        response = self.client.delete(f'/api/v1/documents/{document.id}/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'success': True, 'data': {}})
        self.assertFalse(Document.objects.filter(id=document.id).exists())

    def test_create_rejects_direct_file_url_upload_path(self):
        response = self.client.post(
            '/api/v1/documents/',
            {
                'title': 'Medical Report',
                'category': Document.Category.MEDICAL,
                'file_url': 'https://example.com/doc.pdf',
                'file_size': 128,
                'mime_type': 'application/pdf',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            Document.objects.filter(file_url='https://example.com/doc.pdf').exists()
        )

    @patch('core.storage.generate_upload_url', return_value='https://upload.example')
    def test_upload_url_returns_quarantine_document_key(self, _upload_url):
        response = self.client.post(
            '/api/v1/documents/upload-url/',
            {
                'content_type': 'application/pdf',
                'file_size': 128,
                'filename': 'medical-report.pdf',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()['data']
        self.assertTrue(data['upload_id'])
        self.assertEqual(data['upload_url'], 'https://upload.example')
        self.assertTrue(
            data['raw_key'].startswith(f'quarantine/{self.family.id}/documents/')
        )
        self.assertTrue(data['raw_key'].endswith('.pdf'))
        self.assertEqual(data['expires_in'], 3600)

    @patch('apps.document.views.deidentify_document_task.delay')
    def test_create_with_raw_file_key_schedules_document_deidentification(self, delay):
        raw_key = f'quarantine/{self.family.id}/documents/upload.pdf'

        response = self.client.post(
            '/api/v1/documents/',
            {
                'title': 'Medical Report',
                'category': Document.Category.MEDICAL,
                'raw_file_key': raw_key,
                'file_size': 128,
                'mime_type': 'application/pdf',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        document = Document.objects.get(id=response.json()['data']['id'])
        self.assertEqual(document.raw_file_key, raw_key)
        self.assertTrue(document.redacted_file_key)
        self.assertTrue(document.redacted_file_key.startswith('processed/'))
        self.assertEqual(
            document.deid_status,
            Document.DeidentificationStatus.PROCESSING,
        )
        self.assertFalse(document.file_url)
        delay.assert_called_once_with(document.id)

    @patch('apps.document.views.deidentify_document_task.delay')
    def test_create_with_pdf_raw_file_key_uses_image_processed_key(self, delay):
        raw_key = f'quarantine/{self.family.id}/documents/upload.pdf'

        response = self.client.post(
            '/api/v1/documents/',
            {
                'title': 'Medical Report',
                'category': Document.Category.MEDICAL,
                'raw_file_key': raw_key,
                'file_size': 128,
                'mime_type': 'application/pdf',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        document = Document.objects.get(id=response.json()['data']['id'])
        self.assertEqual(
            document.redacted_file_key,
            f'processed/{self.family.id}/documents/upload.png',
        )
        delay.assert_called_once_with(document.id)

    def test_create_rejects_document_key_outside_request_family_quarantine(self):
        other_family = Family.objects.create(
            name='Other Docs Family',
            elder_name='Other Elder',
            invite_code='555555',
            created_by=self.user,
        )

        response = self.client.post(
            '/api/v1/documents/',
            {
                'title': 'Medical Report',
                'category': Document.Category.MEDICAL,
                'raw_file_key': f'quarantine/{other_family.id}/documents/upload.pdf',
                'file_size': 128,
                'mime_type': 'application/pdf',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Document.objects.filter(raw_file_key__contains='upload.pdf').exists())

    @patch('apps.document.tasks.put_bytes')
    @patch('apps.document.tasks.download_bytes', return_value=b'Email amy@example.com')
    @patch('apps.document.tasks.build_public_url', return_value='https://storage.example/processed.txt')
    @patch('apps.document.tasks.get_deidentification_client')
    def test_document_task_publishes_only_processed_file_url(
        self,
        get_client,
        build_url,
        download_bytes,
        put_bytes,
    ):
        raw_key = f'quarantine/{self.family.id}/documents/report.txt'
        redacted_key = f'processed/{self.family.id}/documents/report.txt'
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Medical Report',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=128,
            mime_type='text/plain',
            raw_file_key=raw_key,
            redacted_file_key=redacted_key,
            deid_status=Document.DeidentificationStatus.PROCESSING,
        )
        get_client.return_value.deidentify_text.return_value = DeidentificationResult(
            text='Email [EMAIL_ADDRESS]',
            findings=[],
        )

        deidentify_document_task(document.id)

        document.refresh_from_db()
        self.assertEqual(document.file_url, 'https://storage.example/processed.txt')
        self.assertEqual(document.deid_status, Document.DeidentificationStatus.COMPLETED)
        download_bytes.assert_called_once_with(raw_key)
        put_bytes.assert_called_once_with(
            redacted_key,
            b'Email [EMAIL_ADDRESS]',
            'text/plain',
        )
        build_url.assert_called_once_with(redacted_key)

    @patch('apps.document.tasks.put_bytes')
    @patch('apps.document.tasks.download_bytes', return_value=b'%PDF-1.7 raw pdf bytes')
    @patch('apps.document.tasks.build_public_url', return_value='https://storage.example/processed.png')
    @patch('apps.document.tasks._rasterize_pdf_to_images')
    @patch('apps.document.tasks.get_deidentification_client')
    def test_document_task_rasterizes_pdf_and_publishes_redacted_image(
        self,
        get_client,
        rasterize,
        build_url,
        download_bytes,
        put_bytes,
    ):
        raw_key = f'quarantine/{self.family.id}/documents/report.pdf'
        redacted_key = f'processed/{self.family.id}/documents/report.pdf'
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Medical Report',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=128,
            mime_type='application/pdf',
            raw_file_key=raw_key,
            redacted_file_key=redacted_key,
            deid_status=Document.DeidentificationStatus.PROCESSING,
        )
        page_png = _png_bytes((255, 0, 0))
        rasterize.return_value = [page_png]
        get_client.return_value.redact_image.return_value = RedactedFile(
            bytes=page_png,
            mime_type='image/png',
            findings=[
                PIIFinding(
                    info_type='EMAIL_ADDRESS',
                    quote='amy@example.com',
                    likelihood='LIKELY',
                )
            ],
        )

        deidentify_document_task(document.id)

        document.refresh_from_db()
        expected_key = f'processed/{self.family.id}/documents/report.png'
        self.assertEqual(document.redacted_file_key, expected_key)
        self.assertEqual(document.file_url, 'https://storage.example/processed.png')
        self.assertEqual(
            document.deid_status,
            Document.DeidentificationStatus.NEEDS_REVIEW,
        )
        self.assertEqual(document.deid_findings, [
            {
                'info_type': 'EMAIL_ADDRESS',
                'likelihood': 'LIKELY',
                'quote_length': len('amy@example.com'),
            }
        ])
        download_bytes.assert_called_once_with(raw_key)
        rasterize.assert_called_once_with(b'%PDF-1.7 raw pdf bytes')
        get_client.return_value.redact_image.assert_called_once_with(
            page_png,
            mime_type='image/png',
        )
        get_client.return_value.inspect_file_bytes.assert_not_called()
        put_bytes.assert_called_once()
        put_key, body, content_type = put_bytes.call_args.args
        self.assertEqual(put_key, expected_key)
        self.assertEqual(content_type, 'image/png')
        self.assertEqual(body[:8], b'\x89PNG\r\n\x1a\n')
        build_url.assert_called_once_with(expected_key)

    @patch('apps.document.tasks.put_bytes')
    @patch('apps.document.tasks.download_bytes', return_value=b'%PDF-1.7 two page pdf')
    @patch('apps.document.tasks.build_public_url', return_value='https://storage.example/processed.png')
    @patch('apps.document.tasks._rasterize_pdf_to_images')
    @patch('apps.document.tasks.get_deidentification_client')
    def test_document_task_stitches_multipage_pdf_into_single_image(
        self,
        get_client,
        rasterize,
        build_url,
        download_bytes,
        put_bytes,
    ):
        raw_key = f'quarantine/{self.family.id}/documents/two-page.pdf'
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Two Page Report',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=4096,
            mime_type='application/pdf',
            raw_file_key=raw_key,
            redacted_file_key=f'processed/{self.family.id}/documents/two-page.pdf',
            deid_status=Document.DeidentificationStatus.PROCESSING,
        )
        page_one = _png_bytes((10, 20, 30), size=(40, 50))
        page_two = _png_bytes((40, 50, 60), size=(30, 70))
        rasterize.return_value = [page_one, page_two]
        get_client.return_value.redact_image.side_effect = [
            RedactedFile(
                bytes=page_one,
                mime_type='image/png',
                findings=[PIIFinding('PERSON_NAME', 'Wang', likelihood='POSSIBLE')],
            ),
            RedactedFile(
                bytes=page_two,
                mime_type='image/png',
                findings=[PIIFinding('TAIWAN_PHONE_NUMBER', '0912345678', likelihood='POSSIBLE')],
            ),
        ]

        result = deidentify_document_task(document.id)

        document.refresh_from_db()
        expected_key = f'processed/{self.family.id}/documents/two-page.png'
        self.assertEqual(result['status'], Document.DeidentificationStatus.COMPLETED)
        self.assertEqual(document.deid_status, Document.DeidentificationStatus.COMPLETED)
        self.assertEqual(document.redacted_file_key, expected_key)
        self.assertEqual(len(document.deid_findings), 2)
        self.assertEqual(
            {finding['info_type'] for finding in document.deid_findings},
            {'PERSON_NAME', 'TAIWAN_PHONE_NUMBER'},
        )
        self.assertEqual(get_client.return_value.redact_image.call_count, 2)
        get_client.return_value.inspect_file_bytes.assert_not_called()
        put_bytes.assert_called_once()
        put_key, body, content_type = put_bytes.call_args.args
        self.assertEqual(put_key, expected_key)
        self.assertEqual(content_type, 'image/png')
        # The stitched image stacks both pages vertically: height is the sum of
        # page heights, width is the widest page.
        import io

        from PIL import Image

        stitched = Image.open(io.BytesIO(body))
        self.assertEqual(stitched.size, (40, 120))
        build_url.assert_called_once_with(expected_key)

    @patch('apps.document.tasks.delete_object')
    def test_cleanup_deletes_completed_raw_files_but_keeps_needs_review(
        self,
        delete_object,
    ):
        old = timezone.now() - timezone.timedelta(hours=25)
        completed = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Completed',
            category=Document.Category.MEDICAL,
            file_url='https://storage.example/processed/completed.pdf',
            file_size=128,
            mime_type='application/pdf',
            raw_file_key=f'quarantine/{self.family.id}/documents/completed.pdf',
            deid_status=Document.DeidentificationStatus.COMPLETED,
            deid_processed_at=old,
        )
        reviewed = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Reviewed',
            category=Document.Category.MEDICAL,
            file_url='https://storage.example/processed/reviewed.pdf',
            file_size=128,
            mime_type='application/pdf',
            raw_file_key=f'quarantine/{self.family.id}/documents/reviewed.pdf',
            deid_status=Document.DeidentificationStatus.NEEDS_REVIEW,
            deid_processed_at=old,
        )
        failed = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Failed',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=128,
            mime_type='application/pdf',
            raw_file_key=f'quarantine/{self.family.id}/documents/failed.pdf',
            deid_status=Document.DeidentificationStatus.FAILED,
            deid_processed_at=old,
        )
        processing = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Processing',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=128,
            mime_type='application/pdf',
            raw_file_key=f'quarantine/{self.family.id}/documents/processing.pdf',
            deid_status=Document.DeidentificationStatus.PROCESSING,
            deid_processed_at=old,
        )

        result = delete_expired_document_quarantine_files_task()

        # Only COMPLETED raw files are purged. NEEDS_REVIEW must be retained
        # until a human approves it, so its quarantine file stays put.
        self.assertEqual(result['deleted'], 1)
        self.assertEqual(
            {call.args[0] for call in delete_object.call_args_list},
            {completed.raw_file_key},
        )
        completed.refresh_from_db()
        reviewed.refresh_from_db()
        failed.refresh_from_db()
        processing.refresh_from_db()
        self.assertEqual(completed.raw_file_key, '')
        self.assertTrue(reviewed.raw_file_key)
        self.assertTrue(failed.raw_file_key)
        self.assertTrue(processing.raw_file_key)

    def test_approve_needs_review_document_marks_completed_and_records_reviewer(self):
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Insurance Scan',
            category=Document.Category.INSURANCE,
            file_url='https://storage.example/processed/scan.png',
            file_size=128,
            mime_type='image/png',
            deid_status=Document.DeidentificationStatus.NEEDS_REVIEW,
            deid_processed_at=timezone.now(),
        )

        response = self.client.post(f'/api/v1/documents/{document.id}/approve/')

        self.assertEqual(response.status_code, 200)
        body = response.json()['data']
        self.assertEqual(body['deid_status'], Document.DeidentificationStatus.COMPLETED)
        self.assertEqual(body['reviewed_by']['id'], str(self.user.id))
        document.refresh_from_db()
        self.assertEqual(
            document.deid_status,
            Document.DeidentificationStatus.COMPLETED,
        )
        self.assertEqual(document.reviewed_by, self.user)
        self.assertIsNotNone(document.reviewed_at)

    def test_approve_rejects_document_not_awaiting_review(self):
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Already Done',
            category=Document.Category.MEDICAL,
            file_url='https://storage.example/processed/done.png',
            file_size=128,
            mime_type='image/png',
            deid_status=Document.DeidentificationStatus.COMPLETED,
            deid_processed_at=timezone.now(),
        )

        response = self.client.post(f'/api/v1/documents/{document.id}/approve/')

        self.assertEqual(response.status_code, 400)
        document.refresh_from_db()
        self.assertIsNone(document.reviewed_by)
        self.assertIsNone(document.reviewed_at)

    @patch('core.storage.generate_upload_url', return_value='https://upload.example')
    @patch('apps.document.views.deidentify_document_task.delay')
    def test_caregiver_cannot_access_document_management_endpoints(
        self,
        delay,
        generate_upload_url,
    ):
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Protected Insurance',
            category=Document.Category.INSURANCE,
            file_url='https://example.com/doc.pdf',
            file_size=128,
            mime_type='application/pdf',
        )
        self.client.force_authenticate(self.caregiver)

        raw_key = f'quarantine/{self.family.id}/documents/caregiver.pdf'
        checks = [
            ('get', '/api/v1/documents/', None),
            ('get', f'/api/v1/documents/{document.id}/', None),
            (
                'post',
                '/api/v1/documents/upload-url/',
                {
                    'content_type': 'application/pdf',
                    'file_size': 128,
                    'filename': 'caregiver.pdf',
                },
            ),
            (
                'post',
                '/api/v1/documents/',
                {
                    'title': 'Caregiver upload',
                    'category': Document.Category.MEDICAL,
                    'raw_file_key': raw_key,
                    'file_size': 128,
                    'mime_type': 'application/pdf',
                },
            ),
            ('delete', f'/api/v1/documents/{document.id}/', None),
            ('post', f'/api/v1/documents/{document.id}/approve/', None),
        ]

        for method, path, data in checks:
            with self.subTest(method=method, path=path):
                request = getattr(self.client, method)
                if data is None:
                    response = request(path)
                else:
                    response = request(path, data, format='json')
                self.assertEqual(response.status_code, 403)
                self.assertEqual(
                    response.json()['error']['code'],
                    'permission_denied',
                )

        self.assertTrue(Document.objects.filter(id=document.id).exists())
        self.assertFalse(
            Document.objects.filter(title='Caregiver upload').exists()
        )
        generate_upload_url.assert_not_called()
        delay.assert_not_called()
