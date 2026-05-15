import re

from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.family.models import Family
from apps.medication.models import Medication
from apps.notification.models import Device, Notification
from apps.notification.tasks import send_medication_reminders
from apps.notification.types import NotificationType
from core.notify import send_notification


class NotificationTypeContractTests(SimpleTestCase):
    def test_supported_notification_types_are_centralized(self):
        self.assertEqual(
            set(NotificationType.values),
            {
                'health_alert',
                'medication_reminder',
                'medication_confirmed',
                'leave_request',
                'leave_status',
                'board_request',
                'board_approved',
                'expense_scanned',
                'sos',
                'sos_resolved',
                'event_reminder',
                'todo_assigned',
                'chat_message',
            },
        )


class MedicationReminderTaskTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='caregiver@example.com',
            password='password123',
            name='Caregiver',
            role=User.Role.CAREGIVER,
        )
        self.family = Family.objects.create(
            name='Reminder Family',
            elder_name='Elder',
            invite_code='333333',
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])

    def test_medication_reminder_task_uses_current_medication_times_field(self):
        current_time = timezone.localtime().strftime('%H:%M')
        medication = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name='Aspirin',
            dosage='100mg',
            frequency=Medication.Frequency.DAILY,
            times=[current_time],
            start_date=timezone.localdate(),
        )

        send_medication_reminders.run()

        notification = Notification.objects.get(user=self.user)
        self.assertEqual(notification.type, 'medication_reminder')
        self.assertEqual(notification.data['medication_id'], str(medication.id))
        self.assertEqual(notification.data['scheduled_time'], current_time)


class NotificationAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='notifications@example.com',
            password='password123',
            name='Notifications',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-notifications@example.com',
            password='password123',
            name='Other Notifications',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Notifications Family',
            elder_name='Elder',
            invite_code='555333',
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def test_list_returns_only_authenticated_users_notifications(self):
        own = Notification.objects.create(
            user=self.user,
            type=NotificationType.CHAT_MESSAGE,
            title='Own',
            body='Visible',
        )
        Notification.objects.create(
            user=self.other_user,
            type=NotificationType.CHAT_MESSAGE,
            title='Other',
            body='Hidden',
        )

        response = self.client.get('/api/v1/notifications/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    @patch('core.translation.translate_text')
    def test_send_notification_translates_title_and_body_with_protected_terms(
        self, translate_text,
    ):
        def fake_translate(masked_text, _source, _targets):
            self.assertNotIn('Amlodipine', masked_text)
            self.assertNotIn('5mg', masked_text)
            placeholders = re.findall(r'__CB_PROTECTED_\d+__', masked_text)
            if 'message' in masked_text:
                return {'id': 'Pesan baru'}
            return {'id': f'Periksa {placeholders[0]} {placeholders[1]}'}

        translate_text.side_effect = fake_translate

        notification = send_notification(
            user=self.user,
            type=NotificationType.CHAT_MESSAGE,
            title='New message',
            body='Check Amlodipine 5mg',
            push=False,
        )

        self.assertEqual(notification.title_translated['zh-TW'], 'New message')
        self.assertEqual(notification.title_translated['id'], 'Pesan baru')
        self.assertEqual(notification.body_translated['zh-TW'], 'Check Amlodipine 5mg')
        self.assertEqual(notification.body_translated['id'], 'Periksa Amlodipine 5mg')

    def test_mark_read_updates_only_owned_notification(self):
        notification = Notification.objects.create(
            user=self.user,
            type=NotificationType.HEALTH_ALERT,
            title='Alert',
            body='Check',
        )

        response = self.client.put(f'/api/v1/notifications/{notification.id}/read/')

        notification.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(notification.is_read)
        self.assertIsNotNone(notification.read_at)
        self.assertTrue(response.json()['data']['is_read'])

    def test_mark_all_read_updates_only_authenticated_user(self):
        own_unread = Notification.objects.create(
            user=self.user,
            type=NotificationType.CHAT_MESSAGE,
            title='Own unread',
            body='Visible',
        )
        own_read = Notification.objects.create(
            user=self.user,
            type=NotificationType.CHAT_MESSAGE,
            title='Own read',
            body='Visible',
            is_read=True,
            read_at=timezone.now(),
        )
        other_unread = Notification.objects.create(
            user=self.other_user,
            type=NotificationType.CHAT_MESSAGE,
            title='Other unread',
            body='Hidden',
        )

        response = self.client.put('/api/v1/notifications/read-all/')

        own_unread.refresh_from_db()
        own_read.refresh_from_db()
        other_unread.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['data']['updated_count'], 1)
        self.assertTrue(own_unread.is_read)
        self.assertTrue(own_read.is_read)
        self.assertFalse(other_unread.is_read)

    def test_register_device_upserts_existing_token_for_user(self):
        response = self.client.post(
            '/api/v1/notifications/device/',
            {
                'device_token': 'token-1',
                'platform': Device.Platform.IOS,
                'device_name': 'Old phone',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)

        response = self.client.post(
            '/api/v1/notifications/device/',
            {
                'device_token': 'token-1',
                'platform': Device.Platform.IOS,
                'device_name': 'New phone',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(Device.objects.filter(user=self.user).count(), 1)
        device = Device.objects.get(user=self.user, device_token='token-1')
        self.assertEqual(device.device_name, 'New phone')
        self.assertTrue(device.is_active)
