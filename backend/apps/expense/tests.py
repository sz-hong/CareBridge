from django.test import TestCase
from django.utils import timezone
from unittest.mock import patch
from rest_framework.test import APIClient

from core.deidentification import RedactedFile
from apps.auth_account.models import User
from apps.expense.models import Expense
from apps.expense.tasks import (
    delete_expired_receipt_quarantine_files_task,
    redact_receipt_image_task,
)
from apps.family.models import Family


class ExpenseAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='expense@example.com',
            password='password123',
            name='Expense User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-expense@example.com',
            password='password123',
            name='Other Expense',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Expense Family',
            elder_name='Elder',
            invite_code='222111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Expense Family',
            elder_name='Other Elder',
            invite_code='222222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_expense(self, **overrides):
        defaults = {
            'family': self.family,
            'recorder': self.user,
            'store_name': 'Care Store',
            'date': timezone.localdate(),
            'items': [{'name': 'Meal', 'category': 'food', 'total': 120}],
            'total_amount': 120,
            'status': Expense.Status.COMPLETED,
        }
        defaults.update(overrides)
        return Expense.objects.create(**defaults)

    def test_list_filters_by_family_and_date_range(self):
        today = timezone.localdate()
        own = self.create_expense(date=today)
        self.create_expense(date=today - timezone.timedelta(days=10))
        self.create_expense(
            family=self.other_family,
            recorder=self.other_user,
            date=today,
        )

        response = self.client.get(
            '/api/v1/expenses/',
            {
                'date_from': today.isoformat(),
                'date_to': today.isoformat(),
            },
        )

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_assigns_family_recorder_and_completed_status(self):
        response = self.client.post(
            '/api/v1/expenses/',
            {
                'store_name': 'Pharmacy',
                'date': timezone.localdate().isoformat(),
                'items': [{'name': 'Medicine', 'category': 'medical', 'total': 350}],
                'total_amount': '350.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        expense = Expense.objects.get(id=response.json()['data']['id'])
        self.assertEqual(expense.family, self.family)
        self.assertEqual(expense.recorder, self.user)
        self.assertEqual(expense.status, Expense.Status.COMPLETED)

    def test_create_normalizes_legacy_expense_item_category_codes(self):
        response = self.client.post(
            '/api/v1/expenses/',
            {
                'store_name': 'Pharmacy',
                'date': timezone.localdate().isoformat(),
                'items': [
                    {'name': 'Medicine', 'category': '醫療保健', 'total': 350},
                    {'name': 'Uncategorized', 'total': 50},
                ],
                'total_amount': '400.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        data = response.json()['data']
        self.assertEqual(data['items'][0]['category'], 'medical')
        self.assertEqual(data['items'][1]['category'], 'other')
        expense = Expense.objects.get(id=data['id'])
        self.assertEqual(expense.items[0]['category'], 'medical')
        self.assertEqual(expense.items[1]['category'], 'other')

    def test_scan_rejects_direct_image_url_upload_path(self):
        response = self.client.post(
            '/api/v1/expenses/scan/',
            {'image_url': 'https://example.com/receipt.jpg'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            Expense.objects.filter(image_url='https://example.com/receipt.jpg').exists()
        )

    def test_create_rejects_direct_image_url_upload_path(self):
        response = self.client.post(
            '/api/v1/expenses/',
            {
                'store_name': 'Pharmacy',
                'date': timezone.localdate().isoformat(),
                'items': [{'name': 'Medicine', 'category': 'medical', 'total': 350}],
                'total_amount': '350.00',
                'image_url': 'https://example.com/receipt.jpg',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            Expense.objects.filter(image_url='https://example.com/receipt.jpg').exists()
        )

    @patch('core.storage.generate_upload_url', return_value='https://upload.example')
    def test_upload_url_returns_quarantine_receipt_key(self, _upload_url):
        response = self.client.post(
            '/api/v1/expenses/upload-url/',
            {'content_type': 'image/jpeg'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()['data']
        self.assertTrue(data['upload_id'])
        self.assertEqual(data['upload_url'], 'https://upload.example')
        self.assertTrue(
            data['raw_key'].startswith(f'quarantine/{self.family.id}/receipts/')
        )
        self.assertTrue(data['raw_key'].endswith('.jpg'))
        self.assertEqual(data['expires_in'], 3600)
        self.assertNotIn('image_url', data)

    @patch('apps.expense.views.redact_receipt_image_task.delay')
    def test_scan_with_raw_key_tracks_deidentification_before_processing(self, delay):
        raw_key = f'quarantine/{self.family.id}/receipts/upload.jpg'

        response = self.client.post(
            '/api/v1/expenses/scan/',
            {'upload_id': 'upload', 'raw_key': raw_key},
            format='json',
        )

        self.assertEqual(response.status_code, 202)
        expense = Expense.objects.get(id=response.json()['data']['id'])
        self.assertEqual(expense.raw_image_key, raw_key)
        self.assertTrue(expense.redacted_image_key)
        self.assertTrue(expense.redacted_image_key.startswith('processed/'))
        self.assertEqual(expense.deid_status, Expense.DeidentificationStatus.PROCESSING)
        self.assertFalse(expense.image_url)
        delay.assert_called_once_with(expense.id)

    def test_scan_rejects_receipt_key_outside_request_family_quarantine(self):
        response = self.client.post(
            '/api/v1/expenses/scan/',
            {
                'upload_id': 'upload',
                'raw_key': f'quarantine/{self.other_family.id}/receipts/upload.jpg',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Expense.objects.filter(raw_image_key__contains='upload.jpg').exists())

    @patch('apps.expense.views.redact_receipt_image_task.delay')
    def test_create_with_raw_image_key_schedules_receipt_deidentification(self, delay):
        raw_key = f'quarantine/{self.family.id}/receipts/manual.jpg'

        response = self.client.post(
            '/api/v1/expenses/',
            {
                'store_name': 'Pharmacy',
                'date': timezone.localdate().isoformat(),
                'items': [{'name': 'Medicine', 'category': 'medical', 'total': 350}],
                'total_amount': '350.00',
                'raw_image_key': raw_key,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        expense = Expense.objects.get(id=response.json()['data']['id'])
        self.assertEqual(expense.raw_image_key, raw_key)
        self.assertEqual(expense.deid_status, Expense.DeidentificationStatus.PROCESSING)
        self.assertFalse(expense.image_url)
        delay.assert_called_once_with(expense.id)

    def test_monthly_summary_uses_completed_current_month_family_expenses(self):
        today = timezone.localdate()
        self.create_expense(
            date=today,
            total_amount=300,
            items=[
                {'name': 'Medicine', 'category': 'medical', 'total': 200},
                {'name': 'Meal', 'category': 'food', 'total': 100},
            ],
        )
        self.create_expense(
            date=today,
            total_amount=50,
            status=Expense.Status.PROCESSING,
            items=[{'name': 'Pending', 'category': 'food', 'total': 50}],
        )
        self.create_expense(
            family=self.other_family,
            recorder=self.other_user,
            date=today,
            total_amount=999,
        )

        response = self.client.get('/api/v1/expenses/monthly/')

        data = response.json()['data']
        self.assertEqual(response.status_code, 200)
        self.assertEqual(data['monthly_total'], 300.0)
        self.assertEqual(
            data['category_breakdown'],
            [
                {'category': 'medical', 'percentage': 66.7},
                {'category': 'food', 'percentage': 33.3},
            ],
        )

    def test_monthly_summary_normalizes_legacy_and_missing_categories(self):
        today = timezone.localdate()
        self.create_expense(
            date=today,
            total_amount=150,
            items=[
                {'name': 'Legacy medical', 'category': '醫療保健', 'total': 100},
                {'name': 'Missing category', 'total': 50},
            ],
        )

        response = self.client.get('/api/v1/expenses/monthly/')

        data = response.json()['data']
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            data['category_breakdown'],
            [
                {'category': 'medical', 'percentage': 66.7},
                {'category': 'other', 'percentage': 33.3},
            ],
        )

    @patch('apps.expense.tasks.put_bytes')
    @patch('apps.expense.tasks.download_bytes', return_value=b'raw-image')
    @patch('apps.expense.tasks.build_public_url', return_value='https://storage.example/processed.jpg')
    @patch('apps.expense.tasks.get_deidentification_client')
    def test_receipt_redaction_task_publishes_only_processed_image_url(
        self,
        get_client,
        build_url,
        download_bytes,
        put_bytes,
    ):
        raw_key = f'quarantine/{self.family.id}/receipts/receipt.jpg'
        redacted_key = f'processed/{self.family.id}/receipts/receipt.jpg'
        expense = self.create_expense(
            image_url=None,
            raw_image_key=raw_key,
            redacted_image_key=redacted_key,
            deid_status=Expense.DeidentificationStatus.PROCESSING,
            status=Expense.Status.PROCESSING,
        )
        get_client.return_value.redact_image.return_value = RedactedFile(
            bytes=b'redacted-image',
            mime_type='image/jpeg',
            findings=[],
        )

        redact_receipt_image_task(expense.id)

        expense.refresh_from_db()
        self.assertEqual(expense.image_url, 'https://storage.example/processed.jpg')
        self.assertEqual(expense.deid_status, Expense.DeidentificationStatus.COMPLETED)
        download_bytes.assert_called_once_with(raw_key)
        put_bytes.assert_called_once_with(redacted_key, b'redacted-image', 'image/jpeg')
        build_url.assert_called_once_with(redacted_key)

    @patch('apps.expense.tasks.delete_object')
    def test_cleanup_deletes_completed_and_reviewed_receipt_raw_files_only(
        self,
        delete_object,
    ):
        old = timezone.now() - timezone.timedelta(hours=25)
        completed = self.create_expense(
            image_url='https://storage.example/processed/completed.jpg',
            raw_image_key=f'quarantine/{self.family.id}/receipts/completed.jpg',
            deid_status=Expense.DeidentificationStatus.COMPLETED,
            deid_processed_at=old,
        )
        reviewed = self.create_expense(
            image_url='https://storage.example/processed/reviewed.jpg',
            raw_image_key=f'quarantine/{self.family.id}/receipts/reviewed.jpg',
            deid_status=Expense.DeidentificationStatus.NEEDS_REVIEW,
            deid_processed_at=old,
        )
        failed = self.create_expense(
            image_url=None,
            raw_image_key=f'quarantine/{self.family.id}/receipts/failed.jpg',
            deid_status=Expense.DeidentificationStatus.FAILED,
            deid_processed_at=old,
        )
        processing = self.create_expense(
            image_url=None,
            raw_image_key=f'quarantine/{self.family.id}/receipts/processing.jpg',
            deid_status=Expense.DeidentificationStatus.PROCESSING,
            deid_processed_at=old,
        )

        result = delete_expired_receipt_quarantine_files_task()

        self.assertEqual(result['deleted'], 2)
        self.assertEqual(
            {call.args[0] for call in delete_object.call_args_list},
            {completed.raw_image_key, reviewed.raw_image_key},
        )
        completed.refresh_from_db()
        reviewed.refresh_from_db()
        failed.refresh_from_db()
        processing.refresh_from_db()
        self.assertEqual(completed.raw_image_key, '')
        self.assertEqual(reviewed.raw_image_key, '')
        self.assertTrue(failed.raw_image_key)
        self.assertTrue(processing.raw_image_key)
