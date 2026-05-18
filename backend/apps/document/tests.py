from django.conf import settings
from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from unittest.mock import patch
from rest_framework.test import APIClient

from core.deidentification import DeidentificationResult, PIIFinding
from apps.auth_account.models import User
from apps.document.models import Document
from apps.document.tasks import (
    deidentify_document_task,
    delete_expired_document_quarantine_files_task,
)
from apps.family.models import Family


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
    def test_create_with_pdf_raw_file_key_uses_text_processed_key(self, delay):
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
            f'processed/{self.family.id}/documents/upload.txt',
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
    @patch('apps.document.tasks.build_public_url', return_value='https://storage.example/processed.txt')
    @patch('apps.document.tasks.get_deidentification_client')
    def test_document_task_inspects_pdf_and_publishes_safe_text_preview(
        self,
        get_client,
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
        get_client.return_value.inspect_file_bytes.return_value = [
            PIIFinding(
                info_type='EMAIL_ADDRESS',
                quote='amy@example.com',
                likelihood='LIKELY',
            )
        ]

        deidentify_document_task(document.id)

        document.refresh_from_db()
        expected_key = f'processed/{self.family.id}/documents/report.txt'
        self.assertEqual(document.redacted_file_key, expected_key)
        self.assertEqual(document.file_url, 'https://storage.example/processed.txt')
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
        get_client.return_value.inspect_file_bytes.assert_called_once_with(
            b'%PDF-1.7 raw pdf bytes',
            mime_type='application/pdf',
        )
        get_client.return_value.redact_image.assert_not_called()
        put_bytes.assert_called_once()
        put_key, body, content_type = put_bytes.call_args.args
        self.assertEqual(put_key, expected_key)
        self.assertEqual(content_type, 'text/plain')
        self.assertIn(b'Processed PDF preview', body)
        self.assertIn(b'EMAIL_ADDRESS', body)
        self.assertNotIn(b'amy@example.com', body)
        build_url.assert_called_once_with(expected_key)

    @patch('apps.document.tasks.put_bytes')
    @patch('apps.document.tasks.download_bytes', return_value=b'%PDF-1.7 large pdf bytes')
    @patch('apps.document.tasks.build_public_url', return_value='https://storage.example/processed.txt')
    @patch('apps.document.tasks.get_deidentification_client')
    def test_document_task_marks_large_pdf_for_review_when_dlp_size_limit_is_hit(
        self,
        get_client,
        build_url,
        download_bytes,
        put_bytes,
    ):
        raw_key = f'quarantine/{self.family.id}/documents/large-report.pdf'
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Large Medical Report',
            category=Document.Category.MEDICAL,
            file_url=None,
            file_size=531732,
            mime_type='application/pdf',
            raw_file_key=raw_key,
            redacted_file_key=f'processed/{self.family.id}/documents/large-report.txt',
            deid_status=Document.DeidentificationStatus.PROCESSING,
        )
        get_client.return_value.inspect_file_bytes.side_effect = RuntimeError(
            '400 Content size 531732 exceeds limit of 524288 [reason: "3" '
            'domain: "dlp.googleapis.com"]'
        )

        result = deidentify_document_task(document.id)

        document.refresh_from_db()
        expected_key = f'processed/{self.family.id}/documents/large-report.txt'
        self.assertEqual(result['status'], Document.DeidentificationStatus.NEEDS_REVIEW)
        self.assertEqual(
            document.deid_status,
            Document.DeidentificationStatus.NEEDS_REVIEW,
        )
        self.assertEqual(document.redacted_file_key, expected_key)
        self.assertEqual(document.file_url, 'https://storage.example/processed.txt')
        self.assertEqual(document.deid_findings, [
            {
                'info_type': 'DLP_CONTENT_SIZE_LIMIT',
                'likelihood': 'LIKELY',
                'quote_length': 0,
            }
        ])
        self.assertEqual(document.raw_file_key, raw_key)
        download_bytes.assert_called_once_with(raw_key)
        get_client.return_value.inspect_file_bytes.assert_called_once_with(
            b'%PDF-1.7 large pdf bytes',
            mime_type='application/pdf',
        )
        get_client.return_value.redact_image.assert_not_called()
        put_bytes.assert_called_once()
        put_key, body, content_type = put_bytes.call_args.args
        self.assertEqual(put_key, expected_key)
        self.assertEqual(content_type, 'text/plain')
        self.assertIn(b'Content size exceeded the DLP inline limit.', body)
        self.assertIn(b'DLP_CONTENT_SIZE_LIMIT', body)
        self.assertNotIn(b'large pdf bytes', body)
        build_url.assert_called_once_with(expected_key)

    @patch('apps.document.tasks.delete_object')
    def test_cleanup_deletes_completed_and_reviewed_document_raw_files_only(
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

        self.assertEqual(result['deleted'], 2)
        self.assertEqual(
            {call.args[0] for call in delete_object.call_args_list},
            {completed.raw_file_key, reviewed.raw_file_key},
        )
        completed.refresh_from_db()
        reviewed.refresh_from_db()
        failed.refresh_from_db()
        processing.refresh_from_db()
        self.assertEqual(completed.raw_file_key, '')
        self.assertEqual(reviewed.raw_file_key, '')
        self.assertTrue(failed.raw_file_key)
        self.assertTrue(processing.raw_file_key)

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
