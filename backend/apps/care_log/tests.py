from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.family.models import Family


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
        self.user.family = self.family
        self.user.save(update_fields=['family'])
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
