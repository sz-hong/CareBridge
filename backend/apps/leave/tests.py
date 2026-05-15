from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.calendar_event.models import Event
from apps.family.models import Family
from apps.leave.models import Leave, LeaveVote


class LeaveAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='leave@example.com',
            password='password123',
            name='Leave User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.second_member = User.objects.create_user(
            email='leave-second@example.com',
            password='password123',
            name='Second Member',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-leave@example.com',
            password='password123',
            name='Other Leave',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Leave Family',
            elder_name='Elder',
            invite_code='666111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Leave Family',
            elder_name='Other Elder',
            invite_code='666222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.second_member.family = self.family
        self.second_member.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_leave(self, **overrides):
        defaults = {
            'family': self.family,
            'applicant': self.user,
            'type': Leave.Type.PERSONAL,
            'start_date': timezone.localdate(),
            'end_date': timezone.localdate() + timezone.timedelta(days=1),
            'days': 2,
            'reason': 'Family care',
        }
        defaults.update(overrides)
        return Leave.objects.create(**defaults)

    def test_list_excludes_other_family_leaves(self):
        own = self.create_leave(reason='Own leave')
        self.create_leave(
            family=self.other_family,
            applicant=self.other_user,
            reason='Other family leave',
        )

        response = self.client.get('/api/v1/leaves/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_assigns_family_applicant_and_days(self):
        start_date = timezone.localdate()
        end_date = start_date + timezone.timedelta(days=2)

        response = self.client.post(
            '/api/v1/leaves/',
            {
                'type': Leave.Type.SICK,
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'reason': 'Medical appointment',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        leave = Leave.objects.get(id=response.json()['data']['id'])
        self.assertEqual(leave.family, self.family)
        self.assertEqual(leave.applicant, self.user)
        self.assertEqual(leave.days, 3)

    @patch('core.translation.translate_text', return_value={'id': 'Janji temu medis'})
    def test_create_translates_leave_reason(self, _translate):
        start_date = timezone.localdate()
        end_date = start_date + timezone.timedelta(days=1)

        response = self.client.post(
            '/api/v1/leaves/',
            {
                'type': Leave.Type.SICK,
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'reason': 'Medical appointment',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        leave = Leave.objects.get(id=response.json()['data']['id'])
        self.assertEqual(leave.reason_translations['zh-TW'], 'Medical appointment')
        self.assertEqual(leave.reason_translations['id'], 'Janji temu medis')

    @patch('apps.notification.tasks.send_notification_task.delay')
    def test_approving_leave_creates_calendar_event_only_once(self, _delay):
        leave = self.create_leave()

        response = self.client.patch(
            f'/api/v1/leaves/{leave.id}/status/',
            {'status': Leave.Status.APPROVED, 'reply': 'Approved'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        leave.refresh_from_db()
        first_event_id = leave.calendar_event_id

        response = self.client.patch(
            f'/api/v1/leaves/{leave.id}/status/',
            {'status': Leave.Status.APPROVED, 'reply': 'Still approved'},
            format='json',
        )

        leave.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(leave.calendar_event_id, first_event_id)
        self.assertEqual(
            Event.objects.filter(source=Event.Source.LEAVE, source_id=leave.id).count(),
            1,
        )

    @patch('apps.notification.tasks.send_notification_task.delay')
    @patch('core.translation.translate_text', return_value={'id': 'Disetujui'})
    def test_update_status_translates_leave_reply(self, _translate, _delay):
        leave = self.create_leave()

        response = self.client.patch(
            f'/api/v1/leaves/{leave.id}/status/',
            {'status': Leave.Status.APPROVED, 'reply': 'Approved'},
            format='json',
        )

        leave.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(leave.reply_translations['zh-TW'], 'Approved')
        self.assertEqual(leave.reply_translations['id'], 'Disetujui')

    def test_votes_auto_approve_after_all_family_members_vote(self):
        leave = self.create_leave()

        response = self.client.post(
            f'/api/v1/leaves/{leave.id}/vote/',
            {'is_available': False},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        leave.refresh_from_db()
        self.assertEqual(leave.status, Leave.Status.PENDING)

        self.client.force_authenticate(self.second_member)
        response = self.client.post(
            f'/api/v1/leaves/{leave.id}/vote/',
            {'is_available': True},
            format='json',
        )

        leave.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(leave.status, Leave.Status.APPROVED)
        self.assertEqual(LeaveVote.objects.filter(leave=leave).count(), 2)
        self.assertIsNotNone(leave.calendar_event)
