from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.family.models import Family
from apps.medication.models import Medication, MedicationConfirmation


class CareLogAPIContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='carelog@example.com',
            password='password123',
            name='Care Log User',
            role=User.Role.CAREGIVER,
        )
        self.family = Family.objects.create(
            name='Care Log Family',
            elder_name='Elder',
            invite_code='555555',
            created_by=self.user,
        )
        self.other_user = User.objects.create_user(
            email='other-carelog@example.com',
            password='password123',
            name='Other Care Log',
            role=User.Role.CAREGIVER,
        )
        self.other_family = Family.objects.create(
            name='Other Care Log Family',
            elder_name='Other Elder',
            invite_code='555556',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def test_date_query_filters_to_that_calendar_day(self):
        target_day = timezone.localdate()
        previous_day = target_day - timedelta(days=1)
        target_log = CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEAL,
            content='Breakfast',
            timestamp=timezone.make_aware(
                datetime.combine(target_day, datetime.min.time()),
                ZoneInfo('Asia/Taipei'),
            ),
        )
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEAL,
            content='Yesterday',
            timestamp=timezone.make_aware(
                datetime.combine(previous_day, datetime.min.time()),
                ZoneInfo('Asia/Taipei'),
            ),
        )

        response = self.client.get(f'/api/v1/care-logs/?date={target_day.isoformat()}')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(target_log.id)})

    def test_list_excludes_other_family_logs(self):
        own_log = CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.NOTE,
            content={'text': 'Own family note'},
            timestamp=timezone.now(),
        )
        CareLog.objects.create(
            family=self.other_family,
            recorder=self.other_user,
            type=CareLog.Type.NOTE,
            content={'text': 'Other family note'},
            timestamp=timezone.now(),
        )

        response = self.client.get('/api/v1/care-logs/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own_log.id)})

    def test_create_assigns_family_and_recorder(self):
        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.VITAL,
                'content': {
                    'temperature': 36.6,
                    'note': 'Morning check',
                },
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        care_log = CareLog.objects.get(id=response.json()['data']['id'])
        self.assertEqual(care_log.family, self.family)
        self.assertEqual(care_log.recorder, self.user)
        self.assertEqual(care_log.type, CareLog.Type.VITAL)

    def test_summary_counts_logs_and_medication_compliance(self):
        now = timezone.now()
        confirmed_log = CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEDICATION,
            content={'medication_name': 'Aspirin'},
            timestamp=now,
        )
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEDICATION,
            content={'medication_name': 'Metformin'},
            timestamp=now,
        )
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEAL,
            content={'text': 'Breakfast'},
            timestamp=now,
        )
        medication = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name='Aspirin',
            dosage='100mg',
            frequency=Medication.Frequency.DAILY,
            times=['08:00'],
            start_date=timezone.localdate(),
        )
        MedicationConfirmation.objects.create(
            medication=medication,
            confirmed_by=self.user,
            scheduled_time='08:00',
            care_log=confirmed_log,
        )

        response = self.client.get('/api/v1/care-logs/summary/')

        data = response.json()['data']
        self.assertEqual(response.status_code, 200)
        self.assertEqual(data['total_logs_by_type'][CareLog.Type.MEDICATION], 2)
        self.assertEqual(data['total_logs_by_type'][CareLog.Type.MEAL], 1)
        self.assertEqual(data['medication_compliance']['confirmed'], 1)
        self.assertEqual(data['medication_compliance']['total'], 2)
        self.assertEqual(data['medication_compliance']['rate'], 0.5)
