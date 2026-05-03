from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.family.models import Family
from apps.medication.models import Medication, MedicationConfirmation


class MedicationAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='medication@example.com',
            password='password123',
            name='Medication User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-medication@example.com',
            password='password123',
            name='Other Medication',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Medication Family',
            elder_name='Elder',
            invite_code='555111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Medication Family',
            elder_name='Other Elder',
            invite_code='555222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_medication(self, **overrides):
        defaults = {
            'family': self.family,
            'created_by': self.user,
            'name': 'Amlodipine',
            'dosage': '5mg',
            'frequency': Medication.Frequency.DAILY,
            'times': ['08:00'],
            'start_date': timezone.localdate(),
        }
        defaults.update(overrides)
        return Medication.objects.create(**defaults)

    def test_list_excludes_other_family_and_expired_medications_by_default(self):
        active = self.create_medication(name='Active medication')
        self.create_medication(
            family=self.other_family,
            created_by=self.other_user,
            name='Other family medication',
        )
        self.create_medication(
            name='Expired medication',
            end_date=timezone.localdate() - timezone.timedelta(days=1),
        )

        response = self.client.get('/api/v1/medications/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(active.id)})

    def test_include_expired_allows_family_expired_medications(self):
        active = self.create_medication(name='Active medication')
        expired = self.create_medication(
            name='Expired medication',
            end_date=timezone.localdate() - timezone.timedelta(days=1),
        )

        response = self.client.get('/api/v1/medications/?include_expired=true')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(active.id), str(expired.id)})

    @patch('apps.medication.views.translate_text', return_value={})
    def test_create_assigns_family_and_creator(self, _translate_text):
        response = self.client.post(
            '/api/v1/medications/',
            {
                'name': 'Metformin',
                'dosage': '500mg',
                'frequency': Medication.Frequency.TWICE_DAILY,
                'times': ['08:00', '20:00'],
                'instructions': 'After meals',
                'start_date': timezone.localdate().isoformat(),
                'reminder_enabled': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        medication = Medication.objects.get(id=response.json()['data']['id'])
        self.assertEqual(medication.family, self.family)
        self.assertEqual(medication.created_by, self.user)
        self.assertEqual(medication.frequency, Medication.Frequency.TWICE_DAILY)

    def test_confirm_creates_confirmation_and_medication_care_log(self):
        medication = self.create_medication(name='Aspirin', dosage='100mg')

        response = self.client.post(
            f'/api/v1/medications/{medication.id}/confirm/',
            {
                'scheduled_time': '08:00',
                'note': 'Taken with breakfast',
                'photo_url': 'https://example.com/photo.jpg',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        confirmation = MedicationConfirmation.objects.get(
            id=response.json()['data']['id']
        )
        self.assertEqual(confirmation.medication, medication)
        self.assertEqual(confirmation.confirmed_by, self.user)
        self.assertEqual(confirmation.scheduled_time, '08:00')
        self.assertEqual(confirmation.care_log.type, CareLog.Type.MEDICATION)
        self.assertEqual(confirmation.care_log.family, self.family)
        self.assertEqual(confirmation.care_log.recorder, self.user)
        self.assertEqual(
            confirmation.care_log.content['medication_id'], str(medication.id)
        )

    def test_today_confirmations_are_scoped_to_authenticated_family(self):
        own = self.create_medication(name='Own medication')
        other = self.create_medication(
            family=self.other_family,
            created_by=self.other_user,
            name='Other medication',
        )
        own_confirmation = MedicationConfirmation.objects.create(
            medication=own,
            confirmed_by=self.user,
            scheduled_time='08:00',
        )
        MedicationConfirmation.objects.create(
            medication=other,
            confirmed_by=self.other_user,
            scheduled_time='09:00',
        )

        response = self.client.get('/api/v1/medications/today_confirmations/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own_confirmation.id)})
