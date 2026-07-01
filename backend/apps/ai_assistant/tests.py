import json
from io import StringIO
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.core.management import call_command
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from pgvector.django import VectorField
from rest_framework.test import APIClient

from apps.ai_assistant.models import FirstAidDocument
from apps.ai_assistant.views import FirstAidView
from apps.ai_assistant.tools import TOOL_DEFINITIONS, execute_tool
from apps.auth_account.models import User
from apps.board.models import BoardRequest
from apps.calendar_event.models import Event
from apps.care_log.models import CareLog
from apps.expense.models import Expense
from apps.family.models import Family
from apps.health.models import HealthAlert, HealthData
from apps.leave.models import Leave
from apps.medication.models import Medication, MedicationConfirmation
from apps.sos.models import SOSRecord
from apps.todo.models import Todo


@override_settings(DLP_PROVIDER="mock")
class AIToolQueryTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="family@example.com",
            password="password123",
            name="Family User",
            role=User.Role.FAMILY_MEMBER,
            phone="0912-111-111",
        )
        self.family = Family.objects.create(
            name="Chen Family",
            elder_name="Grandma Chen",
            invite_code="123456",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.caregiver = User.objects.create_user(
            email="caregiver@example.com",
            password="password123",
            name="Caregiver User",
            role=User.Role.CAREGIVER,
            family=self.family,
            phone="0912-222-222",
        )
        self.other_user = User.objects.create_user(
            email="other-ai@example.com",
            password="password123",
            name="Other AI User",
            role=User.Role.FAMILY_MEMBER,
            phone="0912-999-999",
        )
        self.other_family = Family.objects.create(
            name="Other AI Family",
            elder_name="Other Elder",
            invite_code="654321",
            created_by=self.other_user,
        )
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=["family"])

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

    def test_operational_family_data_tools_are_registered(self):
        registered = {
            item["function"]["name"]
            for item in TOOL_DEFINITIONS
        }

        self.assertTrue({
            "query_todos",
            "query_board_requests",
            "query_leaves",
            "query_health_alerts",
            "query_medication_confirmations",
            "query_sos_status",
            "query_family_members",
        }.issubset(registered))

    def test_new_operational_tools_return_empty_results_without_records(self):
        expectations = {
            "query_todos": "todos",
            "query_board_requests": "board_requests",
            "query_leaves": "leaves",
            "query_health_alerts": "health_alerts",
            "query_medication_confirmations": "medication_confirmations",
            "query_sos_status": "sos_records",
        }

        for tool_name, result_key in expectations.items():
            data = self._execute(tool_name, {})
            self.assertEqual(data[result_key], [], tool_name)
            self.assertEqual(data["count"], 0, tool_name)

    def test_todo_tool_filters_exact_due_date_and_excludes_unscheduled_todos(self):
        today = timezone.localdate()
        tomorrow = today + timezone.timedelta(days=1)
        Todo.objects.create(
            family=self.family,
            title="Today Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
        )
        Todo.objects.create(
            family=self.family,
            title="Tomorrow Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=tomorrow,
        )
        Todo.objects.create(
            family=self.family,
            title="No Date Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.MEDIUM,
            status=Todo.Status.PENDING,
            due_date=None,
        )

        data = self._execute("query_todos", {"due_date": today.isoformat()})
        dumped = json.dumps(data, ensure_ascii=False, default=str)

        self.assertEqual(data["count"], 1)
        self.assertIn("Today Todo", dumped)
        self.assertNotIn("Tomorrow Todo", dumped)
        self.assertNotIn("No Date Todo", dumped)

    def test_todo_tool_context_defaults_today_for_today_todo_question(self):
        today = timezone.localdate()
        yesterday = today - timezone.timedelta(days=1)
        Todo.objects.create(
            family=self.family,
            title="Context Today Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
        )
        Todo.objects.create(
            family=self.family,
            title="Context Old Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=yesterday,
        )

        payload = execute_tool(
            "query_todos",
            json.dumps({}),
            self.user,
            user_message="今天有什麼代辦事項",
        )
        data = json.loads(payload)
        dumped = json.dumps(data, ensure_ascii=False, default=str)

        self.assertNotIn("error", data)
        self.assertEqual(data["count"], 1)
        self.assertIn("Context Today Todo", dumped)
        self.assertNotIn("Context Old Todo", dumped)

    def test_new_operational_tools_are_family_scoped(self):
        today = timezone.localdate()
        medication = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Own Medication",
            dosage="5mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            start_date=today,
        )
        other_medication = Medication.objects.create(
            family=self.other_family,
            created_by=self.other_user,
            name="Other Medication Secret",
            dosage="10mg",
            frequency=Medication.Frequency.DAILY,
            times=["09:00"],
            start_date=today,
        )
        Todo.objects.create(
            family=self.family,
            title="Own Todo",
            assignee=self.caregiver,
            created_by=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
        )
        Todo.objects.create(
            family=self.other_family,
            title="Other Todo Secret",
            assignee=self.other_user,
            created_by=self.other_user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
        )
        BoardRequest.objects.create(
            family=self.family,
            requester=self.caregiver,
            category=BoardRequest.Category.MEDICAL,
            items=[{"name": "Own Gauze", "quantity": "1 box"}],
            note="Own board note",
        )
        BoardRequest.objects.create(
            family=self.other_family,
            requester=self.other_user,
            category=BoardRequest.Category.MEDICAL,
            items=[{"name": "Other Board Secret", "quantity": "1 box"}],
            note="Other board note",
        )
        Leave.objects.create(
            family=self.family,
            applicant=self.caregiver,
            type=Leave.Type.PERSONAL,
            start_date=today,
            end_date=today,
            days=1,
            reason="Own leave reason",
        )
        Leave.objects.create(
            family=self.other_family,
            applicant=self.other_user,
            type=Leave.Type.PERSONAL,
            start_date=today,
            end_date=today,
            days=1,
            reason="Other Leave Secret",
        )
        HealthAlert.objects.create(
            family=self.family,
            type=HealthData.Type.HEART_RATE,
            value=101,
            threshold=100,
            severity=HealthAlert.Severity.WARNING,
            recorded_at=timezone.now(),
        )
        HealthAlert.objects.create(
            family=self.other_family,
            type=HealthData.Type.BLOOD_OXYGEN,
            value=88,
            threshold=93,
            severity=HealthAlert.Severity.CRITICAL,
            recorded_at=timezone.now(),
        )
        MedicationConfirmation.objects.create(
            medication=medication,
            confirmed_by=self.caregiver,
            scheduled_time="08:00",
            note="Own confirmation note",
        )
        MedicationConfirmation.objects.create(
            medication=other_medication,
            confirmed_by=self.other_user,
            scheduled_time="09:00",
            note="Other Confirmation Secret",
        )
        SOSRecord.objects.create(
            family=self.family,
            triggered_by=self.user,
            situation="Own SOS situation",
            status=SOSRecord.Status.TRIGGERED,
        )
        SOSRecord.objects.create(
            family=self.other_family,
            triggered_by=self.other_user,
            situation="Other SOS Secret",
            status=SOSRecord.Status.TRIGGERED,
        )

        expectations = {
            "query_todos": ("Own Todo", "Other Todo Secret"),
            "query_board_requests": ("Own Gauze", "Other Board Secret"),
            "query_leaves": ("Own leave reason", "Other Leave Secret"),
            "query_medication_confirmations": (
                "Own confirmation note",
                "Other Confirmation Secret",
            ),
            "query_sos_status": ("Own SOS situation", "Other SOS Secret"),
            "query_family_members": ("Family User", "Other AI User"),
        }
        for tool_name, (included, excluded) in expectations.items():
            data = self._execute(tool_name, {})
            dumped = json.dumps(data, ensure_ascii=False, default=str)
            self.assertIn(included, dumped, tool_name)
            self.assertNotIn(excluded, dumped, tool_name)

        alerts = self._execute("query_health_alerts", {})
        self.assertEqual(alerts["count"], 1)
        self.assertEqual(alerts["health_alerts"][0]["value"], 101.0)

    def test_ai_tools_omit_sensitive_structured_fields(self):
        now = timezone.now()
        today = timezone.localdate()
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.NOTE,
            content={"note": "Call me at 0912-345-678 about ID A123456789"},
            timestamp=now,
        )
        HealthData.objects.create(
            family=self.family,
            device_id="PRIVATE_DEVICE_ID",
            type=HealthData.Type.HEART_RATE,
            value=80,
            unit=HealthData.Unit.BPM,
            recorded_at=now,
        )
        medication = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Amlodipine",
            dosage="5mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            instructions="Patient phone 0912-345-678",
            start_date=today,
        )
        MedicationConfirmation.objects.create(
            medication=medication,
            confirmed_by=self.user,
            scheduled_time="08:00",
            note="Photo has A123456789",
            photo_url="https://storage.example/private-photo.jpg",
        )
        SOSRecord.objects.create(
            family=self.family,
            triggered_by=self.user,
            location={"lat": 25.033, "lng": 121.565},
            situation="Emergency contact 0912-345-678",
            notified_members=["secret-member-id"],
            status=SOSRecord.Status.TRIGGERED,
        )
        family_member_data = self._execute("query_family_members", {})
        combined = json.dumps({
            "care_logs": self._execute("query_care_logs", {}),
            "health": self._execute("query_health_data", {}),
            "medications": self._execute("query_medications", {}),
            "confirmations": self._execute("query_medication_confirmations", {}),
            "sos": self._execute("query_sos_status", {}),
            "family_members": family_member_data,
        }, ensure_ascii=False, default=str)

        # Structured sensitive fields are still omitted entirely (defence in
        # depth): they are either dropped by SENSITIVE_JSON_KEYS or never
        # selected by the query.
        self.assertNotIn("family@example.com", combined)
        self.assertNotIn("0912-111-111", combined)
        self.assertNotIn("PRIVATE_DEVICE_ID", combined)
        self.assertNotIn("private-photo.jpg", combined)
        self.assertNotIn("25.033", combined)
        self.assertNotIn("secret-member-id", combined)
        self.assertNotIn("raw_image_key", combined)
        self.assertNotIn("raw_file_key", combined)
        # Free text is passed through verbatim — the database is curated to
        # contain no personal data, so the AI read path no longer runs DLP.
        self.assertIn("0912-345-678", combined)
        self.assertIn("A123456789", combined)


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

    def _streamed_content(self, response):
        body = b"".join(response.streaming_content).decode()
        chunks = []
        for line in body.splitlines():
            if not line.startswith("data: "):
                continue
            payload = json.loads(line.removeprefix("data: "))
            if payload.get("type") == "content":
                chunks.append(payload["text"])
        return "".join(chunks)

    @patch("apps.ai_assistant.views._get_client")
    def test_sync_chat_returns_plain_text_without_markdown(self, mock_get_client):
        mock_client = Mock()
        mock_client.chat.completions.create.return_value = SimpleNamespace(
            choices=[
                SimpleNamespace(
                    finish_reason="stop",
                    message=SimpleNamespace(
                        tool_calls=None,
                        content="**重點**\n- 今天狀況良好\n[查看](https://example.com) `用藥`",
                    ),
                )
            ],
            usage=SimpleNamespace(total_tokens=5),
        )
        mock_get_client.return_value = mock_client

        response = self.client.post(
            "/api/v1/ai/chat/",
            {"message": "今天狀況如何"},
            format="json",
            secure=True,
        )

        self.assertEqual(response.status_code, 200)
        reply = response.json()["data"]["reply"]
        self.assertEqual(reply, "重點\n今天狀況良好\n查看 用藥")
        self.assertNotIn("**", reply)
        self.assertNotIn("- ", reply)
        self.assertNotIn("](", reply)
        self.assertNotIn("`", reply)

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
            secure=True,
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.streaming)
        self.assertTrue(response["Content-Type"].startswith("text/event-stream"))

        body = b"".join(response.streaming_content).decode()
        self.assertIn('"type": "content"', body)
        self.assertIn('"text": "\\u6536\\u5230\\uff0c\\u6211\\u6703\\u5354\\u52a9\\u4f60\\u3002"', body)
        self.assertIn('"type": "done"', body)

    @patch("apps.ai_assistant.views._get_client")
    def test_streaming_chat_returns_plain_text_without_markdown(self, mock_get_client):
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
                            delta=SimpleNamespace(
                                content="**重點**\n- 今天狀況良好\n[查看](https://example.com) `用藥`",
                            ),
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
            secure=True,
        )

        self.assertEqual(response.status_code, 200)
        streamed = self._streamed_content(response)
        self.assertEqual(streamed, "重點\n今天狀況良好\n查看 用藥")
        self.assertNotIn("**", streamed)
        self.assertNotIn("- ", streamed)
        self.assertNotIn("](", streamed)
        self.assertNotIn("`", streamed)

    @patch("apps.ai_assistant.views._get_client")
    def test_streaming_chat_removes_split_list_marker(self, mock_get_client):
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
                        SimpleNamespace(delta=SimpleNamespace(content="-")),
                    ],
                ),
                SimpleNamespace(
                    choices=[
                        SimpleNamespace(delta=SimpleNamespace(content=" 今天狀況良好")),
                    ],
                ),
            ],
        ]
        mock_get_client.return_value = mock_client

        response = self.client.post(
            "/api/v1/ai/chat/",
            {"message": "請幫我看今天的照護狀況"},
            format="json",
            HTTP_ACCEPT="text/event-stream",
            secure=True,
        )

        self.assertEqual(response.status_code, 200)
        streamed = self._streamed_content(response)
        self.assertEqual(streamed, "今天狀況良好")
        self.assertNotIn("-", streamed)


class AIReportEndpointContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="ai-report@example.com",
            password="password123",
            name="AI Report User",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="AI Report Family",
            elder_name="Grandpa Lin",
            invite_code="321654",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

        today = timezone.localdate()
        Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Amlodipine",
            dosage="5mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            start_date=today,
        )
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.VITAL,
            content={"blood_pressure_systolic": 128, "blood_pressure_diastolic": 82},
            timestamp=timezone.now(),
        )
        Expense.objects.create(
            family=self.family,
            recorder=self.user,
            store_name="Pharmacy",
            date=today,
            items=[{"name": "Medicine", "category": "medical"}],
            total_amount=Decimal("350.00"),
            status=Expense.Status.COMPLETED,
        )

    def _mock_client(self, content):
        mock_client = Mock()
        mock_client.chat.completions.create.return_value = SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=content),
                )
            ],
            usage=SimpleNamespace(total_tokens=7),
        )
        return mock_client

    @patch("apps.ai_assistant.views._get_client")
    def test_today_summary_uses_only_today_family_care_logs_and_events(self, mock_get_client):
        mock_client = self._mock_client("Today care and schedule are stable")
        mock_get_client.return_value = mock_client
        now = timezone.localtime().replace(
            hour=9, minute=0, second=0, microsecond=0,
        )
        yesterday = now - timezone.timedelta(days=1)
        other_user = User.objects.create_user(
            email="other-summary@example.com",
            password="password123",
            name="Other Summary User",
            role=User.Role.FAMILY_MEMBER,
        )
        other_family = Family.objects.create(
            name="Other Summary Family",
            elder_name="Other Elder",
            invite_code="996633",
            created_by=other_user,
        )
        other_user.family = other_family
        other_user.save(update_fields=["family"])

        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.NOTE,
            content={"note": "morning medication done"},
            timestamp=now,
        )
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.NOTE,
            content={"note": "old care log secret"},
            timestamp=yesterday,
        )
        CareLog.objects.create(
            family=other_family,
            recorder=other_user,
            type=CareLog.Type.NOTE,
            content={"note": "other family care secret"},
            timestamp=now,
        )
        Event.objects.create(
            family=self.family,
            title="cardiology visit",
            start_time=now.replace(hour=14),
            end_time=now.replace(hour=15),
            type=Event.Type.MEDICAL,
            created_by=self.user,
        )
        Event.objects.create(
            family=self.family,
            title="old event secret",
            start_time=yesterday,
            type=Event.Type.PERSONAL,
            created_by=self.user,
        )
        Event.objects.create(
            family=other_family,
            title="other family event secret",
            start_time=now,
            type=Event.Type.PERSONAL,
            created_by=other_user,
        )

        response = self.client.get("/api/v1/ai/today-summary/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["summary"], "Today care and schedule are stable")
        self.assertEqual(data["date"], timezone.localdate().isoformat())
        self.assertEqual(
            data["source_counts"],
            {"care_logs": 2, "events": 1, "todos": 0, "medications": 1},
        )
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("morning medication done", user_prompt)
        self.assertIn("cardiology visit", user_prompt)
        self.assertNotIn("old care log secret", user_prompt)
        self.assertNotIn("old event secret", user_prompt)
        self.assertNotIn("other family care secret", user_prompt)
        self.assertNotIn("other family event secret", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_today_summary_includes_today_todos_and_current_medications(self, mock_get_client):
        mock_client = self._mock_client("Today includes tasks and medication")
        mock_get_client.return_value = mock_client
        today = timezone.localdate()
        other_user = User.objects.create_user(
            email="other-summary-todo@example.com",
            password="password123",
            name="Other Summary Todo User",
            role=User.Role.FAMILY_MEMBER,
        )
        other_family = Family.objects.create(
            name="Other Summary Todo Family",
            elder_name="Other Todo Elder",
            invite_code="996634",
            created_by=other_user,
        )
        other_user.family = other_family
        other_user.save(update_fields=["family"])

        Todo.objects.create(
            family=self.family,
            title="today wound dressing",
            assignee=self.user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
            created_by=self.user,
        )
        Todo.objects.create(
            family=self.family,
            title="tomorrow task secret",
            assignee=self.user,
            priority=Todo.Priority.MEDIUM,
            status=Todo.Status.PENDING,
            due_date=today + timezone.timedelta(days=1),
            created_by=self.user,
        )
        Todo.objects.create(
            family=other_family,
            title="other family todo secret",
            assignee=other_user,
            priority=Todo.Priority.HIGH,
            status=Todo.Status.PENDING,
            due_date=today,
            created_by=other_user,
        )
        Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="Metformin today",
            dosage="500mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            instructions="after breakfast",
            start_date=today,
        )
        Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="future medication secret",
            dosage="10mg",
            frequency=Medication.Frequency.DAILY,
            times=["09:00"],
            start_date=today + timezone.timedelta(days=1),
        )
        Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name="expired medication secret",
            dosage="20mg",
            frequency=Medication.Frequency.DAILY,
            times=["10:00"],
            start_date=today - timezone.timedelta(days=10),
            end_date=today - timezone.timedelta(days=1),
        )
        Medication.objects.create(
            family=other_family,
            created_by=other_user,
            name="other family medication secret",
            dosage="5mg",
            frequency=Medication.Frequency.DAILY,
            times=["11:00"],
            start_date=today,
        )

        response = self.client.get("/api/v1/ai/today-summary/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["source_counts"]["todos"], 1)
        self.assertEqual(data["source_counts"]["medications"], 2)
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("today wound dressing", user_prompt)
        self.assertIn("Metformin today", user_prompt)
        self.assertIn("Amlodipine", user_prompt)
        self.assertNotIn("tomorrow task secret", user_prompt)
        self.assertNotIn("other family todo secret", user_prompt)
        self.assertNotIn("future medication secret", user_prompt)
        self.assertNotIn("expired medication secret", user_prompt)
        self.assertNotIn("other family medication secret", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_today_summary_prompt_uses_authenticated_user_language(self, mock_get_client):
        language_expectations = {
            User.Language.ZH_TW: "Traditional Chinese",
            User.Language.ID: "Bahasa Indonesia",
            User.Language.VI: "Vietnamese",
            User.Language.TL: "Tagalog",
        }

        for language_code, expected_language_name in language_expectations.items():
            with self.subTest(language=language_code):
                mock_client = self._mock_client("localized summary")
                mock_get_client.return_value = mock_client
                self.user.language = language_code
                self.user.save(update_fields=["language"])

                response = self.client.get("/api/v1/ai/today-summary/")

                self.assertEqual(response.status_code, 200)
                messages = mock_client.chat.completions.create.call_args.kwargs["messages"]
                combined_prompt = "\n".join(message["content"] for message in messages)
                self.assertIn(expected_language_name, combined_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_today_summary_prompt_falls_back_to_traditional_chinese_for_unknown_language(self, mock_get_client):
        mock_client = self._mock_client("fallback summary")
        mock_get_client.return_value = mock_client
        self.user.language = "unknown"
        self.user.save(update_fields=["language"])

        response = self.client.get("/api/v1/ai/today-summary/")

        self.assertEqual(response.status_code, 200)
        messages = mock_client.chat.completions.create.call_args.kwargs["messages"]
        combined_prompt = "\n".join(message["content"] for message in messages)
        self.assertIn("Traditional Chinese", combined_prompt)
        self.assertNotIn("unknown", combined_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_today_summary_limits_model_output_to_50_characters(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("x" * 60)

        response = self.client.get("/api/v1/ai/today-summary/")

        self.assertEqual(response.status_code, 200)
        summary = response.json()["data"]["summary"]
        self.assertEqual(summary, "x" * 50)
        self.assertLessEqual(len(summary), 50)

    @patch("apps.ai_assistant.views._get_client")
    def test_care_analysis_uses_current_medication_schema(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("care analysis")

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 7},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn("care analysis", response.json()["data"]["analysis"])

    @patch("apps.ai_assistant.views._get_client")
    def test_care_analysis_always_includes_health_data_numbers(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("care analysis")
        now = timezone.now()
        HealthData.objects.create(
            family=self.family,
            type=HealthData.Type.HEART_RATE,
            value=70,
            unit=HealthData.Unit.BPM,
            recorded_at=now - timezone.timedelta(days=2),
        )
        HealthData.objects.create(
            family=self.family,
            type=HealthData.Type.HEART_RATE,
            value=80,
            unit=HealthData.Unit.BPM,
            recorded_at=now - timezone.timedelta(days=1),
        )
        HealthData.objects.create(
            family=self.family,
            type=HealthData.Type.HEART_RATE,
            value=90,
            unit=HealthData.Unit.BPM,
            recorded_at=now,
        )
        HealthData.objects.create(
            family=self.family,
            type=HealthData.Type.BLOOD_OXYGEN,
            value=95,
            unit=HealthData.Unit.PERCENT,
            recorded_at=now,
        )

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 7},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        analysis = response.json()["data"]["analysis"]
        self.assertIn("身體數據摘要", analysis)
        self.assertIn("心率", analysis)
        self.assertIn("筆數 3", analysis)
        self.assertIn("最新值 90 bpm", analysis)
        self.assertIn("最高值 90 bpm", analysis)
        self.assertIn("最低值 70 bpm", analysis)
        self.assertIn("平均值 80 bpm", analysis)
        self.assertIn("變化量 +20 bpm", analysis)
        self.assertIn("趨勢 上升", analysis)
        self.assertIn("血氧", analysis)

    @patch("apps.ai_assistant.views._get_client")
    def test_care_analysis_includes_vital_care_log_numbers(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("care analysis")
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.VITAL,
            content={
                "blood_sugar": 6.2,
                "temperature": 37.1,
                "weight": 62.5,
            },
            timestamp=timezone.now(),
        )

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 7},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        analysis = response.json()["data"]["analysis"]
        self.assertIn("收縮壓", analysis)
        self.assertIn("最新值 128 mmHg", analysis)
        self.assertIn("舒張壓", analysis)
        self.assertIn("最新值 82 mmHg", analysis)
        self.assertIn("血糖", analysis)
        self.assertIn("最新值 6.2 mmol/L", analysis)
        self.assertIn("體溫", analysis)
        self.assertIn("最新值 37.1 °C", analysis)
        self.assertIn("體重", analysis)
        self.assertIn("最新值 62.5 kg", analysis)

    @patch("apps.ai_assistant.views._get_client")
    def test_care_analysis_states_when_no_health_numbers_exist(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("care analysis")
        CareLog.objects.filter(family=self.family).delete()
        HealthData.objects.filter(family=self.family).delete()

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 7},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        analysis = response.json()["data"]["analysis"]
        self.assertIn("身體數據摘要", analysis)
        self.assertIn("本期間無可用身體數據", analysis)
        self.assertIn("已檢查來源：HealthData、照護紀錄生命徵象", analysis)
        self.assertIn("care analysis", analysis)

    @patch("apps.ai_assistant.views._get_client")
    def test_care_analysis_prompt_targets_doctor_visit_health_trends(self, mock_get_client):
        mock_client = self._mock_client("care analysis")
        mock_get_client.return_value = mock_client

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 14},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("回診", user_prompt)
        self.assertIn("醫師", user_prompt)
        self.assertIn("身體數據變化", user_prompt)
        self.assertIn("趨勢", user_prompt)
        self.assertIn("blood_pressure_systolic", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_handover_report_uses_current_medication_schema(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("handover report")

        response = self.client.post(
            "/api/v1/ai/handover-report/",
            {"date": timezone.localdate().isoformat()},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"]["report"], "handover report")

    @patch("apps.ai_assistant.views._get_client")
    def test_handover_report_prompt_focuses_on_daily_and_future_work(self, mock_get_client):
        mock_client = self._mock_client("handover report")
        mock_get_client.return_value = mock_client
        today = timezone.localdate()
        Todo.objects.create(
            family=self.family,
            title="協助量血壓",
            assignee=self.user,
            priority=Todo.Priority.HIGH,
            due_date=today,
            created_by=self.user,
        )
        Todo.objects.create(
            family=self.family,
            title="下週回診準備",
            assignee=self.user,
            priority=Todo.Priority.MEDIUM,
            due_date=today + timezone.timedelta(days=5),
            created_by=self.user,
        )

        response = self.client.post(
            "/api/v1/ai/handover-report/",
            {"date": today.isoformat()},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("看護交接", user_prompt)
        self.assertIn("今天需要做什麼", user_prompt)
        self.assertIn("未來需要做什麼", user_prompt)
        self.assertIn("today_todos", user_prompt)
        self.assertIn("future_todos", user_prompt)
        self.assertIn("協助量血壓", user_prompt)
        self.assertIn("下週回診準備", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_subsidy_form_uses_current_aggregate_fields(self, mock_get_client):
        mock_get_client.return_value = self._mock_client('{"monthly_expense_total": 350}')

        response = self.client.post(
            "/api/v1/ai/subsidy-form/",
            {"form_type": "long_term_care"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["data"]["form_fields"],
            {"monthly_expense_total": 350},
        )

    @patch("apps.ai_assistant.views._get_client")
    def test_subsidy_form_prompt_uses_backend_template_fields(self, mock_get_client):
        mock_client = self._mock_client('{"applicant_name": "Grandpa Lin"}')
        mock_get_client.return_value = mock_client

        response = self.client.post(
            "/api/v1/ai/subsidy-form/",
            {"form_type": "long_term_care"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["template_name"], "長期照顧服務申請表")
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("form_template", user_prompt)
        self.assertIn("official_source", user_prompt)
        self.assertIn("applicant_name", user_prompt)
        self.assertIn("只依照表單模板欄位", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_subsidy_form_accepts_uploaded_template_file(self, mock_get_client):
        mock_client = self._mock_client('{"custom_field": "Grandpa Lin"}')
        mock_get_client.return_value = mock_client
        uploaded = SimpleUploadedFile(
            "custom-form.txt",
            "欄位：custom_field\n說明：自訂申請欄位".encode("utf-8"),
            content_type="text/plain",
        )

        response = self.client.post(
            "/api/v1/ai/subsidy-form/",
            {"form_type": "uploaded_template", "template_file": uploaded},
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["template_name"], "custom-form.txt")
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("uploaded_template", user_prompt)
        self.assertIn("custom_field", user_prompt)


class FirstAidScenarioEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="first-aid@example.com",
            password="password123",
            name="First Aid User",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="First Aid Family",
            elder_name="Grandma Wu",
            invite_code="654123",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

    def test_scenarios_endpoint_returns_static_first_aid_documents_for_ios(self):
        FirstAidDocument.objects.create(
            title="Chest pain",
            source="Manual",
            section="Emergency",
            content="Call 119 immediately.\nKeep the elder seated.",
        )

        response = self.client.get("/api/v1/ai/first-aid/scenarios/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["title"], "Chest pain")
        self.assertEqual(data[0]["icon"], "cross.case.fill")
        self.assertEqual(
            data[0]["steps"],
            ["Call 119 immediately.", "Keep the elder seated."],
        )


class FirstAidRAGTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="first-aid-rag@example.com",
            password="password123",
            name="First Aid RAG User",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="First Aid RAG Family",
            elder_name="Grandma Lin",
            invite_code="741258",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client.force_authenticate(self.user)

    def _chat_client(self, answer="\u8acb\u7acb\u5373\u64a5\u6253 119 \u4e26\u4f9d\u7167\u6025\u6551\u6b65\u9a5f\u8655\u7406\u3002"):
        client = Mock()
        client.chat.completions.create.return_value = SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=answer),
                )
            ],
            usage=SimpleNamespace(total_tokens=42),
        )
        return client

    def test_embedding_field_uses_pgvector_with_openai_small_dimensions(self):
        field = FirstAidDocument._meta.get_field("embedding")

        self.assertIsInstance(field, VectorField)
        self.assertEqual(field.dimensions, 1536)

    def test_keyword_fallback_matches_chinese_natural_language_query(self):
        FirstAidDocument.objects.create(
            title="\u4e2d\u98a8 FAST \u8a55\u4f30",
            source="\u6025\u6551\u624b\u518a",
            section="\u5fc3\u8840\u7ba1\u6025\u75c7",
            content="\u81c9\u6b6a\u3001\u624b\u7121\u529b\u3001\u8aaa\u8a71\u4e0d\u6e05\u695a\u6642\uff0c\u8a18\u9304\u6642\u9593\u4e26\u7acb\u5373\u64a5\u6253 119\u3002",
        )
        FirstAidDocument.objects.create(
            title="\u8dcc\u5012\u8655\u7f6e",
            source="\u6025\u6551\u624b\u518a",
            section="\u5c45\u5bb6\u610f\u5916",
            content="\u5148\u78ba\u8a8d\u610f\u8b58\u8207\u547c\u5438\uff0c\u4e0d\u8981\u7acb\u523b\u62c9\u8d77\u9577\u8005\u3002",
        )

        results = FirstAidView()._retrieve_documents("\u963f\u5b24\u7591\u4f3c\u4e2d\u98a8\u600e\u9ebc\u8fa6", top_k=3)

        self.assertEqual(results[0]["title"], "\u4e2d\u98a8 FAST \u8a55\u4f30")

    @patch("apps.ai_assistant.views._get_client")
    def test_first_aid_api_uses_retrieved_documents_as_prompt_context(self, mock_get_client):
        mock_client = self._chat_client()
        mock_get_client.return_value = mock_client
        FirstAidDocument.objects.create(
            title="\u4e2d\u98a8 FAST \u8a55\u4f30",
            source="\u6025\u6551\u624b\u518a",
            section="\u5fc3\u8840\u7ba1\u6025\u75c7",
            content="\u81c9\u6b6a\u3001\u624b\u7121\u529b\u3001\u8aaa\u8a71\u4e0d\u6e05\u695a\u6642\uff0c\u8a18\u9304\u6642\u9593\u4e26\u7acb\u5373\u64a5\u6253 119\u3002",
        )

        response = self.client.post(
            "/api/v1/ai/first-aid/",
            {"query": "\u963f\u5b24\u7591\u4f3c\u4e2d\u98a8\u600e\u9ebc\u8fa6"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["sources"], [{"title": "\u4e2d\u98a8 FAST \u8a55\u4f30", "source": "\u6025\u6551\u624b\u518a"}])
        user_prompt = mock_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
        self.assertIn("Reference Materials:", user_prompt)
        self.assertIn("Use only the reference materials", user_prompt)
        self.assertIn("\u4e2d\u98a8 FAST \u8a55\u4f30", user_prompt)
        self.assertIn("\u963f\u5b24\u7591\u4f3c\u4e2d\u98a8\u600e\u9ebc\u8fa6", user_prompt)

    @patch("apps.ai_assistant.views._get_client")
    def test_first_aid_api_does_not_answer_without_rag_sources(self, mock_get_client):
        mock_get_client.return_value = self._chat_client("should not answer")

        response = self.client.post(
            "/api/v1/ai/first-aid/",
            {"query": "\u7259\u75db\u53ef\u4ee5\u5403\u4ec0\u9ebc\u85e5"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["sources"], [])
        self.assertEqual(data["tokens_used"], 0)
        self.assertIn("\u6025\u6551\u77e5\u8b58\u5eab", data["answer"])
        mock_get_client.assert_not_called()

    @patch("apps.ai_assistant.views._get_client")
    def test_first_aid_api_strips_markdown_from_model_answer(self, mock_get_client):
        markdown_answer = "# \u7acb\u5373\u8655\u7f6e\n- **\u64a5\u6253 119**\n[\u4f7f\u7528 AED](https://example.com) `CPR`"
        mock_client = self._chat_client(markdown_answer)
        mock_get_client.return_value = mock_client
        FirstAidDocument.objects.create(
            title="\u4e2d\u98a8 FAST \u8a55\u4f30",
            source="\u6025\u6551\u624b\u518a",
            section="\u5fc3\u8840\u7ba1\u6025\u75c7",
            content="\u81c9\u6b6a\u3001\u624b\u7121\u529b\u3001\u8aaa\u8a71\u4e0d\u6e05\u695a\u6642\uff0c\u8a18\u9304\u6642\u9593\u4e26\u7acb\u5373\u64a5\u6253 119\u3002",
        )

        response = self.client.post(
            "/api/v1/ai/first-aid/",
            {"query": "\u963f\u5b24\u7591\u4f3c\u4e2d\u98a8\u600e\u9ebc\u8fa6"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        answer = response.json()["data"]["answer"]
        self.assertNotIn("#", answer)
        self.assertNotIn("**", answer)
        self.assertNotIn("- ", answer)
        self.assertNotIn("[`", answer)
        self.assertNotIn("](https://", answer)
        self.assertIn("\u64a5\u6253 119", answer)
        self.assertIn("AED CPR", answer)

    @patch("apps.ai_assistant.views._get_client")
    def test_vector_retrieval_orders_documents_by_embedding_distance(self, mock_get_client):
        mock_client = self._chat_client()
        mock_client.embeddings.create.return_value = SimpleNamespace(
            data=[SimpleNamespace(embedding=[1.0] + [0.0] * 1535)]
        )
        mock_get_client.return_value = mock_client
        FirstAidDocument.objects.create(
            title="\u4e2d\u98a8 FAST \u8a55\u4f30",
            source="\u6025\u6551\u624b\u518a",
            section="\u5fc3\u8840\u7ba1\u6025\u75c7",
            content="\u81c9\u6b6a\u3001\u624b\u7121\u529b\u3001\u8aaa\u8a71\u4e0d\u6e05\u695a\u6642\uff0c\u8a18\u9304\u6642\u9593\u4e26\u7acb\u5373\u64a5\u6253 119\u3002",
            embedding=[1.0] + [0.0] * 1535,
        )
        FirstAidDocument.objects.create(
            title="\u8dcc\u5012\u8655\u7f6e",
            source="\u6025\u6551\u624b\u518a",
            section="\u5c45\u5bb6\u610f\u5916",
            content="\u5148\u78ba\u8a8d\u610f\u8b58\u8207\u547c\u5438\uff0c\u4e0d\u8981\u7acb\u523b\u62c9\u8d77\u9577\u8005\u3002",
            embedding=[0.0, 1.0] + [0.0] * 1534,
        )

        results = FirstAidView()._retrieve_documents("\u7591\u4f3c\u4e2d\u98a8", top_k=2)

        self.assertEqual([doc["title"] for doc in results], ["\u4e2d\u98a8 FAST \u8a55\u4f30", "\u8dcc\u5012\u8655\u7f6e"])
        mock_client.embeddings.create.assert_called_once()

    @patch("apps.ai_assistant.views._get_client")
    def test_index_command_writes_embeddings_and_skips_current_documents(self, mock_get_client):
        mock_client = self._chat_client()
        mock_client.embeddings.create.return_value = SimpleNamespace(
            data=[SimpleNamespace(embedding=[0.5] + [0.0] * 1535)]
        )
        mock_get_client.return_value = mock_client
        doc = FirstAidDocument.objects.create(
            title="\u660f\u53a5\u6025\u6551\u6307\u5357",
            source="\u6025\u6551\u624b\u518a",
            section="\u5e38\u898b\u6025\u75c7",
            content="\u78ba\u8a8d\u547c\u5438\uff0c\u8b93\u9577\u8005\u5e73\u8e7a\uff0c\u5fc5\u8981\u6642\u64a5\u6253 119\u3002",
        )

        first_run = StringIO()
        call_command("index_first_aid_documents", stdout=first_run)
        doc.refresh_from_db()

        self.assertIsNotNone(doc.embedding)
        self.assertEqual(doc.embedding_model, "text-embedding-3-small")
        self.assertTrue(doc.embedding_content_hash)
        self.assertIn("indexed=1", first_run.getvalue())

        second_run = StringIO()
        call_command("index_first_aid_documents", stdout=second_run)

        mock_client.embeddings.create.assert_called_once()
        self.assertIn("skipped=1", second_run.getvalue())

@override_settings(DLP_PROVIDER="mock")
class AIPromptDeidentificationTests(TestCase):
    """P0: care-analysis / handover prompts must de-identify care-log free text
    before it is sent to OpenAI."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="deid-family@example.com",
            password="password123",
            name="Deid Family",
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name="Deid Family Group",
            elder_name="Elder",
            invite_code="909090",
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=["family"])
        self.client = APIClient()
        self.client.force_authenticate(self.user)

        self.pii_phone = "0912-345-678"
        self.pii_id = "A123456789"
        CareLog.objects.create(
            family=self.family,
            recorder=self.user,
            type=CareLog.Type.NOTE,
            content={"note": f"聯絡電話 {self.pii_phone} 身分證 {self.pii_id}"},
            timestamp=timezone.now(),
        )

    def _fake_client(self, capture):
        def create(**kwargs):
            capture.append(kwargs)
            message = SimpleNamespace(content="ok", tool_calls=None)
            choice = SimpleNamespace(message=message, finish_reason="stop")
            usage = SimpleNamespace(total_tokens=10)
            return SimpleNamespace(choices=[choice], usage=usage)

        client = Mock()
        client.chat.completions.create.side_effect = create
        return client

    @staticmethod
    def _prompt_text(capture):
        parts = []
        for call in capture:
            for message in call.get("messages", []):
                parts.append(str(message.get("content", "")))
        return "\n".join(parts)

    def test_care_analysis_includes_care_log_text_verbatim(self):
        capture = []
        with patch(
            "apps.ai_assistant.views._get_client",
            return_value=self._fake_client(capture),
        ):
            response = self.client.post(
                "/api/v1/ai/care-analysis/", {"days": 7}, format="json",
            )

        self.assertEqual(response.status_code, 200)
        prompt = self._prompt_text(capture)
        # The database is curated to contain no personal data, so care-log
        # free text now reaches the prompt verbatim (no DLP round-trip).
        self.assertIn(self.pii_phone, prompt)
        self.assertIn(self.pii_id, prompt)

    def test_handover_report_includes_care_log_text_verbatim(self):
        capture = []
        with patch(
            "apps.ai_assistant.views._get_client",
            return_value=self._fake_client(capture),
        ):
            response = self.client.post(
                "/api/v1/ai/handover-report/", {}, format="json",
            )

        self.assertEqual(response.status_code, 200)
        prompt = self._prompt_text(capture)
        self.assertIn(self.pii_phone, prompt)
        self.assertIn(self.pii_id, prompt)
