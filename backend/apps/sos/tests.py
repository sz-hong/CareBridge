from django.test import TestCase
from rest_framework.test import APIClient
from types import SimpleNamespace
from unittest.mock import patch

from apps.auth_account.models import User
from apps.family.models import Family
from apps.notification.models import Notification
from apps.notification.types import NotificationType
from apps.sos.models import SOSRecord


class SOSAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='sos@example.com',
            password='password123',
            name='SOS User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.member = User.objects.create_user(
            email='sos-member@example.com',
            password='password123',
            name='SOS Member',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-sos@example.com',
            password='password123',
            name='Other SOS',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='SOS Family',
            elder_name='Elder',
            invite_code='121212',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other SOS Family',
            elder_name='Other Elder',
            invite_code='343434',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.member.family = self.family
        self.member.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_sos(self, **overrides):
        defaults = {
            'family': self.family,
            'triggered_by': self.user,
            'location': {'lat': 25.0, 'lng': 121.5},
            'situation': 'Need help',
            'status': SOSRecord.Status.TRIGGERED,
        }
        defaults.update(overrides)
        return SOSRecord.objects.create(**defaults)

    @patch('core.notify.broadcast_family')
    def test_trigger_creates_record_and_tracks_notified_members(self, broadcast_family):
        broadcast_family.return_value = [
            SimpleNamespace(user_id=self.user.id),
            SimpleNamespace(user_id=self.member.id),
        ]

        response = self.client.post(
            '/api/v1/sos/trigger/',
            {
                'location': {'lat': 25.0, 'lng': 121.5},
                'situation': 'Fall detected',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        sos = SOSRecord.objects.get(id=response.json()['data']['id'])
        self.assertEqual(sos.family, self.family)
        self.assertEqual(sos.triggered_by, self.user)
        self.assertEqual(sos.status, SOSRecord.Status.TRIGGERED)
        self.assertEqual(sos.notified_members, [str(self.user.id), str(self.member.id)])
        self.assertEqual(response.json()['data']['notified_count'], 2)
        broadcast_family.assert_called_once()
        _, kwargs = broadcast_family.call_args
        self.assertFalse(kwargs['push'])
        self.assertNotIn('exclude_user', kwargs)

    @patch('core.notify._send_push_to_user')
    def test_trigger_creates_in_app_notifications_for_triggerer_and_family(self, send_push):
        response = self.client.post(
            '/api/v1/sos/trigger/',
            {
                'location': {'lat': 25.0, 'lng': 121.5},
                'situation': 'Fall detected',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        sos = SOSRecord.objects.get(id=response.json()['data']['id'])
        notifications = Notification.objects.filter(
            type=NotificationType.SOS,
            data__sos_id=str(sos.id),
        )
        self.assertEqual(
            {notification.user_id for notification in notifications},
            {self.user.id, self.member.id},
        )
        self.assertEqual(response.json()['data']['notified_count'], 2)
        self.assertEqual(set(sos.notified_members), {str(self.user.id), str(self.member.id)})
        send_push.assert_not_called()

    def test_history_is_scoped_to_authenticated_family(self):
        own = self.create_sos(situation='Own SOS')
        self.create_sos(
            family=self.other_family,
            triggered_by=self.other_user,
            situation='Other SOS',
        )

        response = self.client.get('/api/v1/sos/history/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    @patch('apps.notification.tasks.broadcast_family_task.delay')
    def test_resolve_marks_family_sos_resolved(self, _delay):
        sos = self.create_sos()

        response = self.client.patch(f'/api/v1/sos/{sos.id}/resolve/')

        sos.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(sos.status, SOSRecord.Status.RESOLVED)
        self.assertIsNotNone(sos.resolved_at)

    def test_resolve_other_family_sos_returns_not_found(self):
        sos = self.create_sos(
            family=self.other_family,
            triggered_by=self.other_user,
            status=SOSRecord.Status.TRIGGERED,
        )

        response = self.client.patch(f'/api/v1/sos/{sos.id}/resolve/')

        self.assertEqual(response.status_code, 404)
        sos.refresh_from_db()
        self.assertEqual(sos.status, SOSRecord.Status.TRIGGERED)
        self.assertIsNone(sos.resolved_at)
