from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.document.models import Document
from apps.expense.models import Expense
from apps.family.models import Family


class AdminAPIAuthTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.non_staff = User.objects.create_user(
            email="member@example.com",
            password="password123",
            name="Member",
        )
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )

    def test_admin_overview_requires_authentication(self):
        response = self.client.get("/api/v1/admin/overview/")

        self.assertEqual(response.status_code, 401)

    def test_admin_overview_rejects_non_staff_users(self):
        self.client.force_authenticate(self.non_staff)

        response = self.client.get("/api/v1/admin/overview/")

        self.assertEqual(response.status_code, 403)

    @override_settings(AWS_ACCESS_KEY_ID="", AWS_SECRET_ACCESS_KEY="")
    def test_staff_user_can_read_admin_overview(self):
        self.client.force_authenticate(self.staff)

        response = self.client.get("/api/v1/admin/overview/")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        self.assertIn("kpis", response.json()["data"])

    def test_admin_endpoints_reject_head_requests(self):
        self.client.force_authenticate(self.staff)

        response = self.client.head("/api/v1/admin/overview/")

        self.assertEqual(response.status_code, 405)


class AdminAPITableTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.client.force_authenticate(self.staff)
        self.family = Family.objects.create(
            name="Alpha Family",
            elder_name="Elder",
            invite_code="123456",
            created_by=self.staff,
        )
        self.staff.family = self.family
        self.staff.save(update_fields=["family"])

    def test_tables_endpoint_returns_fixed_admin_pagination_shape(self):
        response = self.client.get(
            "/api/v1/admin/tables/users/",
            {"page_size": 200, "search": "staff"},
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["success"])
        self.assertEqual(
            set(payload["data"].keys()),
            {"results", "count", "next", "previous", "page", "page_size"},
        )
        self.assertEqual(payload["data"]["page_size"], 100)
        self.assertNotIn("password", payload["data"]["results"][0])

    def test_unknown_admin_table_is_rejected(self):
        response = self.client.get("/api/v1/admin/tables/not_allowed/")

        self.assertEqual(response.status_code, 404)

    def test_table_date_range_filters_between_bounds(self):
        old_user = User.objects.create_user(
            email="old@example.com",
            password="password123",
            name="Old User",
        )
        old_timestamp = timezone.now() - timedelta(days=3)
        User.objects.filter(id=old_user.id).update(
            created_at=old_timestamp,
            updated_at=old_timestamp,
        )

        response = self.client.get(
            "/api/v1/admin/tables/users/",
            {
                "date_from": (timezone.now() - timedelta(days=1)).isoformat(),
                "date_to": (timezone.now() + timedelta(days=1)).isoformat(),
                "page_size": 100,
            },
        )

        self.assertEqual(response.status_code, 200)
        emails = {item["email"] for item in response.json()["data"]["results"]}
        self.assertIn("staff@example.com", emails)
        self.assertNotIn("old@example.com", emails)

    def test_activity_endpoint_infers_recent_model_changes(self):
        response = self.client.get("/api/v1/admin/activity/", {"limit": 5})

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertIn("results", data)
        self.assertIn("next_cursor", data)
        self.assertLessEqual(len(data["results"]), 5)
        self.assertIn("table", data["results"][0])
        self.assertIn("record_id", data["results"][0])
        self.assertIn("action", data["results"][0])
        self.assertIn("created_at", data["results"][0])

    def test_record_detail_includes_related_storage_objects(self):
        expense = Expense.objects.create(
            family=self.family,
            recorder=self.staff,
            store_name="Pharmacy",
            date=timezone.localdate(),
            items=[{"name": "Medicine", "category": "medical", "total": 120}],
            total_amount=120,
            image_url="https://storage.carebridge-lab.com/carebridge-storage/receipts/family/receipt.jpg",
        )

        response = self.client.get(f"/api/v1/admin/records/expenses/{expense.id}/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["record"]["id"], str(expense.id))
        self.assertEqual(data["raw"]["id"], str(expense.id))
        self.assertEqual(
            data["related_files"][0]["object_key"],
            "receipts/family/receipt.jpg",
        )

    def test_record_detail_rejects_invalid_uuid(self):
        response = self.client.get("/api/v1/admin/records/users/not-a-uuid/")

        self.assertEqual(response.status_code, 404)


class AdminAPIStorageAndLogsTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.client.force_authenticate(self.staff)
        self.family = Family.objects.create(
            name="Storage Family",
            elder_name="Elder",
            invite_code="777777",
            created_by=self.staff,
        )

    @override_settings(
        AWS_ACCESS_KEY_ID="test-key",
        AWS_SECRET_ACCESS_KEY="test-secret",
        AWS_STORAGE_BUCKET_NAME="carebridge-storage",
    )
    @patch("apps.admin_api.views.get_s3_client")
    def test_overview_reports_storage_listing_failure(self, mock_client):
        mock_client.return_value.list_objects_v2.side_effect = RuntimeError("storage down")

        response = self.client.get("/api/v1/admin/overview/")

        self.assertEqual(response.status_code, 200)
        alert_titles = {
            alert["title"] for alert in response.json()["data"]["alerts"]
        }
        self.assertIn("Storage listing failed", alert_titles)

    @override_settings(
        AWS_STORAGE_BUCKET_NAME="carebridge-storage",
        AWS_S3_ENDPOINT_URL="https://storage.carebridge-lab.com",
    )
    @patch("apps.admin_api.views.get_s3_client")
    def test_storage_endpoint_lists_objects_and_marks_linked_files(self, mock_client):
        Document.objects.create(
            family=self.family,
            title="Document",
            category=Document.Category.MEDICAL,
            file_url="https://storage.carebridge-lab.com/carebridge-storage/docs/report.pdf",
            file_size=100,
            mime_type="application/pdf",
            uploaded_by=self.staff,
        )
        mock_client.return_value.list_objects_v2.return_value = {
            "KeyCount": 2,
            "Contents": [
                {
                    "Key": "docs/report.pdf",
                    "Size": 100,
                    "LastModified": timezone.now(),
                },
                {
                    "Key": "orphan/file.jpg",
                    "Size": 200,
                    "LastModified": timezone.now(),
                },
            ],
        }

        response = self.client.get("/api/v1/admin/storage/objects/")

        self.assertEqual(response.status_code, 200)
        results = response.json()["data"]["results"]
        linked = next(item for item in results if item["object_key"] == "docs/report.pdf")
        orphan = next(item for item in results if item["object_key"] == "orphan/file.jpg")
        self.assertFalse(linked["orphan"])
        self.assertEqual(linked["linked_table"], "documents")
        self.assertTrue(orphan["orphan"])

    @override_settings(AWS_STORAGE_BUCKET_NAME="carebridge-storage")
    def test_storage_endpoint_rejects_unknown_bucket(self):
        response = self.client.get(
            "/api/v1/admin/storage/objects/",
            {"bucket": "../secrets"},
        )

        self.assertEqual(response.status_code, 400)

    @patch("apps.admin_api.views.read_log_stream")
    def test_logs_endpoint_reads_allow_listed_stream_only(self, mock_reader):
        mock_reader.return_value = [
            {
                "timestamp": "2026-05-08T10:30:00+08:00",
                "level": "INFO",
                "message": "Runtime started",
                "request_id": None,
            }
        ]

        response = self.client.get(
            "/api/v1/admin/logs/",
            {"stream": "runtime", "lines": 999},
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["stream"], "runtime")
        self.assertEqual(data["lines"][0]["level"], "INFO")
        mock_reader.assert_called_once_with("runtime", 500)

    def test_logs_endpoint_rejects_path_traversal_stream(self):
        response = self.client.get(
            "/api/v1/admin/logs/",
            {"stream": "../runtime"},
        )

        self.assertEqual(response.status_code, 400)


class AdminAPICORSTests(TestCase):
    @override_settings(
        CORS_ALLOWED_ORIGINS=[
            "https://shao-zhen.com",
            "http://127.0.0.1:4173",
            "http://localhost:4321",
        ],
        CORS_ALLOW_ALL_ORIGINS=False,
    )
    def test_cors_preflight_allows_dashboard_origin(self):
        response = self.client.options(
            "/api/v1/admin/overview/",
            HTTP_ORIGIN="https://shao-zhen.com",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="authorization,content-type,accept",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response["Access-Control-Allow-Origin"],
            "https://shao-zhen.com",
        )

    @override_settings(
        CORS_ALLOWED_ORIGINS=["https://shao-zhen.com"],
        CORS_ALLOW_ALL_ORIGINS=False,
    )
    def test_cors_preflight_rejects_unknown_origin(self):
        response = self.client.options(
            "/api/v1/admin/overview/",
            HTTP_ORIGIN="https://unknown.example",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET",
        )

        self.assertNotIn("Access-Control-Allow-Origin", response)
