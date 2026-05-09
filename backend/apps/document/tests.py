from django.test import TestCase
from unittest.mock import patch
from rest_framework.test import APIClient

from core.deidentification import DeidentificationResult
from apps.auth_account.models import User
from apps.document.models import Document
from apps.document.tasks import deidentify_document_task
from apps.family.models import Family


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
