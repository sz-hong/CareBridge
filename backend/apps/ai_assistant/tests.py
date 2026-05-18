import json
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.ai_assistant.models import FirstAidDocument
from apps.ai_assistant.tools import TOOL_DEFINITIONS, execute_tool
from apps.auth_account.models import User
from apps.board.models import BoardRequest
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

    def test_ai_tools_omit_sensitive_fields_and_redact_free_text(self):
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

        self.assertNotIn("0912-345-678", combined)
        self.assertNotIn("A123456789", combined)
        self.assertNotIn("family@example.com", combined)
        self.assertNotIn("0912-111-111", combined)
        self.assertNotIn("PRIVATE_DEVICE_ID", combined)
        self.assertNotIn("private-photo.jpg", combined)
        self.assertNotIn("25.033", combined)
        self.assertNotIn("secret-member-id", combined)
        self.assertNotIn("raw_image_key", combined)
        self.assertNotIn("raw_file_key", combined)
        self.assertIn("[TAIWAN_PHONE_NUMBER]", combined)


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
    def test_care_analysis_uses_current_medication_schema(self, mock_get_client):
        mock_get_client.return_value = self._mock_client("care analysis")

        response = self.client.post(
            "/api/v1/ai/care-analysis/",
            {"days": 7},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"]["analysis"], "care analysis")

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
