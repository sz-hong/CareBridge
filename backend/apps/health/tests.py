from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.family.models import Family
from apps.health.models import HealthAlert, HealthAlertThreshold, HealthData


class HealthAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='health@example.com',
            password='password123',
            name='Health User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-health@example.com',
            password='password123',
            name='Other Health',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Health Family',
            elder_name='Elder',
            invite_code='444111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Health Family',
            elder_name='Other Elder',
            invite_code='444222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.family.health_binding_user = self.user
        self.family.health_binding_device_id = 'watch-1'
        self.family.save(update_fields=[
            'health_binding_user',
            'health_binding_device_id',
        ])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_data(self, **overrides):
        defaults = {
            'family': self.family,
            'type': HealthData.Type.HEART_RATE,
            'value': 72,
            'unit': HealthData.Unit.BPM,
            'recorded_at': timezone.now(),
        }
        defaults.update(overrides)
        return HealthData.objects.create(**defaults)

    def test_list_filters_by_family_and_type(self):
        own = self.create_data(type=HealthData.Type.HEART_RATE, value=70)
        self.create_data(type=HealthData.Type.STEP_COUNT, value=1000, unit=HealthData.Unit.STEPS)
        self.create_data(
            family=self.other_family,
            type=HealthData.Type.HEART_RATE,
            value=88,
        )

        response = self.client.get('/api/v1/health-data/?type=heart_rate')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_accepts_blood_pressure_metric_types_used_by_seed_data(self):
        type_field = HealthData._meta.get_field('type')
        self.assertGreaterEqual(
            type_field.max_length,
            len('blood_pressure_diastolic'),
        )
        self.assertIn('blood_pressure_systolic', HealthData.Type.values)
        self.assertIn('blood_pressure_diastolic', HealthData.Type.values)
        self.assertIn('mmHg', HealthData.Unit.values)

        systolic = self.create_data(
            type='blood_pressure_systolic',
            value=128,
            unit='mmHg',
        )
        diastolic = self.create_data(
            type='blood_pressure_diastolic',
            value=82,
            unit='mmHg',
        )

        self.assertEqual(systolic.type, 'blood_pressure_systolic')
        self.assertEqual(diastolic.type, 'blood_pressure_diastolic')

    def test_sync_accepts_blood_pressure_metrics(self):
        recorded_at = timezone.now().isoformat()

        response = self.client.post(
            '/api/v1/health-data/sync/',
            {
                'data': [
                    {
                        'type': 'blood_pressure_systolic',
                        'value': '128',
                        'unit': 'mmHg',
                        'recorded_at': recorded_at,
                        'device_id': 'watch-1',
                    },
                    {
                        'type': 'blood_pressure_diastolic',
                        'value': '82',
                        'unit': 'mmHg',
                        'recorded_at': recorded_at,
                        'device_id': 'watch-1',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()['data']['synced'], 2)
        self.assertEqual(
            set(HealthData.objects.values_list('type', flat=True)),
            {'blood_pressure_systolic', 'blood_pressure_diastolic'},
        )

    @patch('apps.notification.tasks.broadcast_family_task.delay')
    def test_sync_deduplicates_points_and_returns_threshold_alerts(self, _delay):
        HealthAlertThreshold.objects.create(
            family=self.family,
            heart_rate_high=100,
            heart_rate_low=50,
            blood_oxygen_low=93.0,
            updated_by=self.user,
        )
        recorded_at = timezone.now().isoformat()

        response = self.client.post(
            '/api/v1/health-data/sync/',
            {
                'data': [
                    {
                        'type': HealthData.Type.HEART_RATE,
                        'value': '120',
                        'unit': HealthData.Unit.BPM,
                        'recorded_at': recorded_at,
                        'device_id': 'watch-1',
                    },
                    {
                        'type': HealthData.Type.HEART_RATE,
                        'value': '120',
                        'unit': HealthData.Unit.BPM,
                        'recorded_at': recorded_at,
                        'device_id': 'watch-1',
                    },
                ],
            },
            format='json',
        )

        body = response.json()['data']
        self.assertEqual(response.status_code, 201)
        self.assertEqual(body['synced'], 1)
        self.assertEqual(body['duplicates'], 1)
        self.assertEqual(len(body['alerts']), 1)
        self.assertEqual(HealthData.objects.filter(family=self.family).count(), 1)
        self.assertEqual(HealthAlert.objects.filter(family=self.family).count(), 1)

    def test_dashboard_returns_latest_value_per_type_for_family(self):
        older = timezone.now() - timezone.timedelta(hours=2)
        latest = timezone.now()
        self.create_data(type=HealthData.Type.HEART_RATE, value=70, recorded_at=older)
        heart_rate = self.create_data(
            type=HealthData.Type.HEART_RATE,
            value=81,
            recorded_at=latest,
        )
        oxygen = self.create_data(
            type=HealthData.Type.BLOOD_OXYGEN,
            value=97.5,
            unit=HealthData.Unit.PERCENT,
            recorded_at=latest,
        )
        self.create_data(
            family=self.other_family,
            type=HealthData.Type.HEART_RATE,
            value=150,
            recorded_at=latest + timezone.timedelta(minutes=1),
        )

        response = self.client.get('/api/v1/health-data/dashboard/')

        self.assertEqual(response.status_code, 200)
        data = response.json()['data']
        self.assertEqual(data['heart_rate']['id'], str(heart_rate.id))
        self.assertEqual(data['blood_oxygen']['id'], str(oxygen.id))

    def test_acknowledge_alert_marks_family_alert(self):
        alert = HealthAlert.objects.create(
            family=self.family,
            type=HealthData.Type.BLOOD_OXYGEN,
            value=90,
            threshold=93,
            severity=HealthAlert.Severity.CRITICAL,
            recorded_at=timezone.now(),
        )

        response = self.client.put(
            f'/api/v1/health-data/alerts/{alert.id}/acknowledge/',
            format='json',
        )

        alert.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(alert.acknowledged_by, self.user)
        self.assertIsNotNone(alert.acknowledged_at)

    def test_weekly_steps_returns_seven_family_scoped_daily_totals(self):
        today = timezone.localdate()
        self.create_data(
            type=HealthData.Type.STEP_COUNT,
            value=1000,
            unit=HealthData.Unit.STEPS,
            recorded_at=timezone.make_aware(
                timezone.datetime.combine(today, timezone.datetime.min.time())
            ),
        )
        self.create_data(
            type=HealthData.Type.STEP_COUNT,
            value=500,
            unit=HealthData.Unit.STEPS,
            recorded_at=timezone.make_aware(
                timezone.datetime.combine(today, timezone.datetime.min.time())
            ) + timezone.timedelta(hours=1),
        )
        self.create_data(
            family=self.other_family,
            type=HealthData.Type.STEP_COUNT,
            value=9999,
            unit=HealthData.Unit.STEPS,
            recorded_at=timezone.now(),
        )

        response = self.client.get('/api/v1/health-data/weekly-steps/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['data'], [0, 0, 0, 0, 0, 0, 1500])
