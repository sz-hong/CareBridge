from uuid import uuid4

from django.test import SimpleTestCase, TestCase
from django.urls import Resolver404, resolve
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.expense.models import Expense
from apps.family.models import Family
from apps.health.models import HealthData
from apps.board.models import BoardRequest
from apps.medication.models import Medication
from apps.sos.models import SOSRecord


class APIRouteContractTests(SimpleTestCase):
    def test_care_log_and_medication_routes_use_trailing_slashes(self):
        item_id = uuid4()
        expected_paths = [
            "/api/v1/care-logs/",
            "/api/v1/care-logs/summary/",
            f"/api/v1/care-logs/{item_id}/",
            "/api/v1/medications/",
            "/api/v1/medications/today_confirmations/",
            f"/api/v1/medications/{item_id}/",
            f"/api/v1/medications/{item_id}/confirm/",
        ]

        for path in expected_paths:
            with self.subTest(path=path):
                self.assertIsNotNone(resolve(path))

    def test_care_log_and_medication_router_paths_reject_missing_trailing_slash(self):
        item_id = uuid4()
        rejected_paths = [
            "/api/v1/care-logs",
            "/api/v1/care-logs/summary",
            f"/api/v1/care-logs/{item_id}",
            "/api/v1/medications",
            "/api/v1/medications/today_confirmations",
            f"/api/v1/medications/{item_id}",
            f"/api/v1/medications/{item_id}/confirm",
        ]

        for path in rejected_paths:
            with self.subTest(path=path):
                with self.assertRaises(Resolver404):
                    resolve(path)


class FamilyScopeContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="family-a@example.com",
            password="password123",
            name="Family A",
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email="family-b@example.com",
            password="password123",
            name="Family B",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="Family A",
            elder_name="Elder A",
            invite_code="111111",
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name="Family B",
            elder_name="Elder B",
            invite_code="222222",
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

    def test_family_scoped_lists_exclude_other_family_records(self):
        today = timezone.localdate()
        now = timezone.now()

        own_med = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Own medication",
            dosage="5mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            start_date=today,
        )
        Medication.objects.create(
            family=self.other_family,
            created_by=self.other_user,
            name="Other medication",
            dosage="10mg",
            frequency=Medication.Frequency.DAILY,
            times=["09:00"],
            start_date=today,
        )
        own_expense = Expense.objects.create(
            family=self.family,
            recorder=self.user,
            store_name="Own pharmacy",
            date=today,
            items=[{"name": "Medicine", "category": "medical"}],
            total_amount="100.00",
        )
        Expense.objects.create(
            family=self.other_family,
            recorder=self.other_user,
            store_name="Other pharmacy",
            date=today,
            items=[{"name": "Medicine", "category": "medical"}],
            total_amount="200.00",
        )
        own_health = HealthData.objects.create(
            family=self.family,
            type=HealthData.Type.HEART_RATE,
            value="72",
            unit=HealthData.Unit.BPM,
            recorded_at=now,
        )
        HealthData.objects.create(
            family=self.other_family,
            type=HealthData.Type.HEART_RATE,
            value="95",
            unit=HealthData.Unit.BPM,
            recorded_at=now,
        )
        own_sos = SOSRecord.objects.create(
            family=self.family,
            triggered_by=self.user,
            status=SOSRecord.Status.TRIGGERED,
        )
        SOSRecord.objects.create(
            family=self.other_family,
            triggered_by=self.other_user,
            status=SOSRecord.Status.TRIGGERED,
        )

        checks = [
            ("/api/v1/medications/", str(own_med.id)),
            ("/api/v1/expenses/", str(own_expense.id)),
            ("/api/v1/health-data/", str(own_health.id)),
            ("/api/v1/sos/history/", str(own_sos.id)),
        ]
        for path, expected_id in checks:
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200)
                ids = {str(item["id"]) for item in response.json()["data"]}
                self.assertEqual(ids, {expected_id})

    def test_family_scoped_retrieve_rejects_other_family_record(self):
        other_med = Medication.objects.create(
            family=self.other_family,
            created_by=self.other_user,
            name="Other medication",
            dosage="10mg",
            frequency=Medication.Frequency.DAILY,
            times=["09:00"],
            start_date=timezone.localdate(),
        )

        response = self.client.get(f"/api/v1/medications/{other_med.id}/")

        self.assertEqual(response.status_code, 404)


class ErrorResponseContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="errors@example.com",
            password="password123",
            name="Errors",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="Error Family",
            elder_name="Elder",
            invite_code="333444",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

    def test_manual_bad_request_uses_error_envelope(self):
        board_request = BoardRequest.objects.create(
            family=self.family,
            requester=self.user,
            category=BoardRequest.Category.DAILY,
            items=[{"name": "Tissue", "quantity": "1"}],
        )

        response = self.client.patch(
            f"/api/v1/board/{board_request.id}/status/",
            {"status": "invalid"},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json(),
            {
                "success": False,
                "error": {
                    "code": "invalid_status",
                    "message": "Invalid status.",
                },
            },
        )

    def test_manual_not_found_uses_error_envelope(self):
        missing_id = uuid4()

        response = self.client.put(
            f"/api/v1/health-data/alerts/{missing_id}/acknowledge/"
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(
            response.json(),
            {
                "success": False,
                "error": {
                    "code": "not_found",
                    "message": "Alert not found.",
                },
            },
        )


class CaregiverDeletePermissionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.owner = User.objects.create_user(
            email="delete-owner@example.com",
            password="password123",
            name="Delete Owner",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="Delete Permission Family",
            elder_name="Elder",
            invite_code="987654",
            created_by=self.owner,
        )
        self.caregiver = User.objects.create_user(
            email="delete-caregiver@example.com",
            password="password123",
            name="Delete Caregiver",
            role=User.Role.CAREGIVER,
            family=self.family,
        )
        self.client.force_authenticate(self.caregiver)

    def test_caregiver_cannot_delete_own_account(self):
        response = self.client.delete("/api/v1/auth/account/")

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "permission_denied")
        self.assertTrue(User.objects.filter(id=self.caregiver.id).exists())
