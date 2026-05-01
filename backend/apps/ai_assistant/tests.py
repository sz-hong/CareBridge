import json
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from apps.ai_assistant.tools import TOOL_DEFINITIONS, execute_tool
from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.expense.models import Expense
from apps.family.models import Family
from apps.health.models import HealthData
from apps.medication.models import Medication


class AIToolQueryTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="family@example.com",
            password="password123",
            name="Family User",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="Chen Family",
            elder_name="Grandma Chen",
            invite_code="123456",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])

    def _execute(self, tool_name, args):
        payload = execute_tool(tool_name, json.dumps(args), self.user)
        data = json.loads(payload)
        self.assertNotIn("error", data)
        return data

    def test_medication_tool_uses_times_field(self):
        Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Metformin",
            dosage="500mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00", "18:00"],
            instructions="Take after meals",
            start_date=timezone.localdate(),
        )

        data = self._execute("query_medications", {"active_only": True})

        self.assertEqual(data["count"], 1)
        self.assertEqual(data["medications"][0]["times"], ["08:00", "18:00"])
        self.assertEqual(data["medications"][0]["time_slots"], ["08:00", "18:00"])

    def test_expense_tool_uses_current_expense_fields(self):
        Expense.objects.create(
            family=self.family,
            recorder=self.user,
            store_name="Pharmacy",
            date=timezone.localdate(),
            items=[{"name": "Medicine", "category": "medical"}],
            total_amount=Decimal("350.00"),
            status=Expense.Status.COMPLETED,
        )

        data = self._execute("query_expenses", {"days": 30})

        self.assertEqual(data["count"], 1)
        self.assertEqual(data["total"], 350.0)
        self.assertEqual(data["expenses"][0]["store_name"], "Pharmacy")
        self.assertEqual(data["expenses"][0]["category"], "medical")
        self.assertEqual(data["expenses"][0]["total_amount"], 350.0)

    def test_health_and_care_log_schema_match_model_enums(self):
        health_tool = next(
            item for item in TOOL_DEFINITIONS
            if item["function"]["name"] == "query_health_data"
        )
        care_log_tool = next(
            item for item in TOOL_DEFINITIONS
            if item["function"]["name"] == "query_care_logs"
        )

        self.assertEqual(
            health_tool["function"]["parameters"]["properties"]["data_type"]["enum"],
            list(HealthData.Type.values),
        )
        self.assertEqual(
            care_log_tool["function"]["parameters"]["properties"]["log_type"]["enum"],
            list(CareLog.Type.values),
        )
