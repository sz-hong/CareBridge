import json
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

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


class AIChatStreamingContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="ai-stream@example.com",
            password="password123",
            name="AI Stream User",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="AI Stream Family",
            elder_name="Grandma Lin",
            invite_code="345678",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

    @patch("apps.ai_assistant.views._get_client")
    def test_chat_accepts_event_stream_accept_header_without_query_param(self, mock_get_client):
        mock_client = Mock()
        mock_client.chat.completions.create.side_effect = [
            SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        finish_reason="stop",
                        message=SimpleNamespace(tool_calls=None),
                    )
                ],
                usage=SimpleNamespace(total_tokens=3),
            ),
            [
                SimpleNamespace(
                    choices=[
                        SimpleNamespace(
                            delta=SimpleNamespace(content="收到，我會協助你。"),
                        )
                    ]
                )
            ],
        ]
        mock_get_client.return_value = mock_client

        response = self.client.post(
            "/api/v1/ai/chat/",
            {"message": "請幫我看今天的照護狀況"},
            format="json",
            HTTP_ACCEPT="text/event-stream",
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.streaming)
        self.assertTrue(response["Content-Type"].startswith("text/event-stream"))

        body = b"".join(response.streaming_content).decode()
        self.assertIn('"type": "content"', body)
        self.assertIn('"text": "\\u6536\\u5230\\uff0c\\u6211\\u6703\\u5354\\u52a9\\u4f60\\u3002"', body)
        self.assertIn('"type": "done"', body)
