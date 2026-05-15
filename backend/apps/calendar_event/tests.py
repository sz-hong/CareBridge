from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.calendar_event.models import Event
from apps.family.models import Family


class CalendarEventAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='calendar@example.com',
            password='password123',
            name='Calendar User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-calendar@example.com',
            password='password123',
            name='Other Calendar',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Calendar Family',
            elder_name='Elder',
            invite_code='333111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Calendar Family',
            elder_name='Other Elder',
            invite_code='333222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_event(self, **overrides):
        defaults = {
            'family': self.family,
            'created_by': self.user,
            'title': 'Clinic visit',
            'start_time': timezone.now() + timezone.timedelta(hours=1),
            'end_time': timezone.now() + timezone.timedelta(hours=2),
            'type': Event.Type.MEDICAL,
        }
        defaults.update(overrides)
        return Event.objects.create(**defaults)

    def test_list_filters_by_family_type_and_start_range(self):
        start = timezone.now() + timezone.timedelta(days=1)
        matching = self.create_event(type=Event.Type.MEDICAL, start_time=start)
        self.create_event(type=Event.Type.PERSONAL, start_time=start)
        self.create_event(
            type=Event.Type.MEDICAL,
            start_time=start - timezone.timedelta(days=2),
        )
        self.create_event(
            family=self.other_family,
            created_by=self.other_user,
            type=Event.Type.MEDICAL,
            start_time=start,
        )

        response = self.client.get(
            '/api/v1/events/',
            {
                'type': Event.Type.MEDICAL,
                'start_after': (start - timezone.timedelta(hours=1)).isoformat(),
                'start_before': (start + timezone.timedelta(hours=1)).isoformat(),
            },
        )

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(matching.id)})

    def test_create_assigns_family_created_by_and_manual_source(self):
        start = timezone.now() + timezone.timedelta(hours=3)

        response = self.client.post(
            '/api/v1/events/',
            {
                'title': 'Rehab session',
                'start_time': start.isoformat(),
                'end_time': (start + timezone.timedelta(hours=1)).isoformat(),
                'location': 'Clinic',
                'type': Event.Type.REHAB,
                'reminder_minutes': 30,
                'note': 'Bring report',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        event = Event.objects.get(id=response.json()['data']['id'])
        self.assertEqual(event.family, self.family)
        self.assertEqual(event.created_by, self.user)
        self.assertEqual(event.source, Event.Source.MANUAL)
        self.assertEqual(event.reminder_minutes, 30)

    @patch('core.translation.translate_text', side_effect=[
        {'id': 'Sesi rehabilitasi'},
        {'id': 'Bawa laporan'},
    ])
    def test_create_translates_event_title_and_note(self, _translate):
        start = timezone.now() + timezone.timedelta(hours=3)

        response = self.client.post(
            '/api/v1/events/',
            {
                'title': 'Rehab session',
                'start_time': start.isoformat(),
                'location': 'Clinic',
                'type': Event.Type.REHAB,
                'note': 'Bring report',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        event = Event.objects.get(id=response.json()['data']['id'])
        self.assertEqual(event.title_translated['zh-TW'], 'Rehab session')
        self.assertEqual(event.title_translated['id'], 'Sesi rehabilitasi')
        self.assertEqual(event.note_translated['zh-TW'], 'Bring report')
        self.assertEqual(event.note_translated['id'], 'Bawa laporan')

    def test_batch_create_assigns_family_and_created_by_to_each_event(self):
        start = timezone.now() + timezone.timedelta(days=2)

        response = self.client.post(
            '/api/v1/events/batch/',
            {
                'events': [
                    {
                        'title': 'Morning medicine',
                        'start_time': start.isoformat(),
                        'type': Event.Type.MEDICATION,
                    },
                    {
                        'title': 'Afternoon walk',
                        'start_time': (start + timezone.timedelta(hours=6)).isoformat(),
                        'type': Event.Type.PERSONAL,
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        ids = [item['id'] for item in response.json()['data']]
        events = Event.objects.filter(id__in=ids)
        self.assertEqual(events.count(), 2)
        self.assertTrue(all(event.family == self.family for event in events))
        self.assertTrue(all(event.created_by == self.user for event in events))
