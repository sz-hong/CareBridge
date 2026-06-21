import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

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

    @patch(
        'apps.care_log.serializers.generate_download_url',
        return_value='https://download.example/photo.jpg',
    )
    def test_create_accepts_family_scoped_photo_key(self, _download_url):
        photo_key = f'care-logs/{self.family.id}/photos/morning.jpg'

        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.MEAL,
                'content': {'description': 'Breakfast'},
                'photo_key': photo_key,
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        data = response.json()['data']
        care_log = CareLog.objects.get(id=data['id'])
        self.assertEqual(care_log.photo_key, photo_key)
        self.assertEqual(data['photo_url'], 'https://download.example/photo.jpg')
        self.assertNotIn('photo_key', data)

    def test_create_rejects_photo_key_from_other_family(self):
        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.ACTIVITY,
                'content': {'activity_type': 'Walk'},
                'photo_key': (
                    f'care-logs/{self.other_family.id}/photos/foreign.jpg'
                ),
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            CareLog.objects.filter(photo_key__contains='foreign.jpg').exists()
        )

    def test_create_rejects_direct_photo_url(self):
        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.MEAL,
                'content': {'description': 'Lunch'},
                'photo_url': 'https://untrusted.example/photo.jpg',
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    @patch(
        'core.storage.generate_upload_url',
        return_value='https://upload.example/photo',
    )
    def test_upload_url_uses_family_care_log_photo_path(self, _upload_url):
        response = self.client.post(
            '/api/v1/care-logs/upload-url/',
            {'content_type': 'image/jpeg'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()['data']
        self.assertEqual(data['upload_url'], 'https://upload.example/photo')
        self.assertTrue(
            data['photo_key'].startswith(
                f'care-logs/{self.family.id}/photos/'
            )
        )
        self.assertTrue(data['photo_key'].endswith('.jpg'))

    def test_upload_url_rejects_non_image_content_type(self):
        response = self.client.post(
            '/api/v1/care-logs/upload-url/',
            {'content_type': 'application/pdf'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    @patch('core.storage.delete_object')
    def test_delete_removes_photo_object(self, delete_object):
        self.user.role = User.Role.FAMILY_MEMBER
        self.user.save(update_fields=['role'])
        photo_key = f'care-logs/{self.family.id}/photos/delete-me.jpg'
        care_log = CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.MEAL,
            content={'description': 'Dinner'},
            photo_key=photo_key,
            timestamp=timezone.now(),
        )

        response = self.client.delete(f'/api/v1/care-logs/{care_log.id}/')

        self.assertEqual(response.status_code, 200)
        delete_object.assert_called_once_with(photo_key)

    @patch('core.translation.translate_text', return_value={'id': 'Catatan pagi'})
    def test_create_translates_care_log_text_content(self, _translate):
        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.NOTE,
                'content': {'text': 'Morning note'},
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        care_log = CareLog.objects.get(id=response.json()['data']['id'])
        self.assertEqual(care_log.content_translated['text']['zh-TW'], 'Morning note')
        self.assertEqual(care_log.content_translated['text']['id'], 'Catatan pagi')

    @patch('core.translation.translate_text')
    def test_create_protects_medication_name_and_mixed_note(self, translate_text):
        def fake_translate(masked_text, _source, _targets):
            self.assertNotIn('Aspirin', masked_text)
            self.assertNotIn('08:00', masked_text)
            placeholders = re.findall(r'__CB_PROTECTED_\d+__', masked_text)
            self.assertGreaterEqual(len(placeholders), 2)
            return {'id': f'{placeholders[0]} diberikan pada {placeholders[1]}'}

        translate_text.side_effect = fake_translate

        response = self.client.post(
            '/api/v1/care-logs/',
            {
                'type': CareLog.Type.MEDICATION,
                'content': {
                    'medication_name': 'Aspirin',
                    'note': 'Aspirin given at 08:00',
                },
                'timestamp': timezone.now().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        care_log = CareLog.objects.get(id=response.json()['data']['id'])
        self.assertEqual(
            care_log.content_translated['medication_name']['id'],
            'Aspirin',
        )
        self.assertEqual(
            care_log.content_translated['note']['id'],
            'Aspirin diberikan pada 08:00',
        )

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
