from datetime import timedelta
from unittest.mock import patch

from django.apps import apps
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.document.models import Document
from apps.expense.models import Expense
from apps.family.models import Family
from apps.medication.models import Medication
from apps.todo.models import Todo


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


    def test_staff_can_list_admin_table_index_with_capabilities(self):
        self.client.force_authenticate(self.staff)

        response = self.client.get("/api/v1/admin/tables/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        tables = {item["table"]: item for item in data["results"]}
        self.assertIn("todos", tables)
        self.assertIn("medications", tables)
        self.assertIn("messages", tables)
        self.assertFalse(tables["users"]["capabilities"]["create"])
        self.assertFalse(tables["families"]["capabilities"]["update"])
        self.assertTrue(tables["todos"]["capabilities"]["update"])
        self.assertTrue(tables["medications"]["capabilities"]["delete"])
        self.assertTrue(tables["expenses"]["capabilities"]["create"])
        self.assertTrue(tables["expenses"]["capabilities"]["update"])
        self.assertTrue(tables["expenses"]["capabilities"]["delete"])

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
        AWS_S3_PUBLIC_ENDPOINT_URL="https://storage.carebridge-lab.com",
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

    @override_settings(
        AWS_STORAGE_BUCKET_NAME="carebridge-storage",
        AWS_S3_ENDPOINT_URL="https://storage.carebridge-lab.com",
        AWS_S3_PUBLIC_ENDPOINT_URL="https://storage.carebridge-lab.com",
    )
    @patch("apps.admin_api.views.get_s3_client")
    def test_storage_endpoint_links_care_log_photo_key(self, mock_client):
        care_log = CareLog.objects.create(
            family=self.family,
            recorder=self.staff,
            type=CareLog.Type.NOTE,
            content={"note": "with photo"},
            photo_key="care_logs/family-1/photo.jpg",
            timestamp=timezone.now(),
        )
        mock_client.return_value.list_objects_v2.return_value = {
            "KeyCount": 1,
            "Contents": [
                {
                    "Key": "care_logs/family-1/photo.jpg",
                    "Size": 300,
                    "LastModified": timezone.now(),
                },
            ],
        }

        response = self.client.get("/api/v1/admin/storage/objects/")

        self.assertEqual(response.status_code, 200)
        results = response.json()["data"]["results"]
        photo = next(
            item
            for item in results
            if item["object_key"] == "care_logs/family-1/photo.jpg"
        )
        self.assertFalse(photo["orphan"])
        self.assertEqual(photo["linked_table"], "care_logs")
        self.assertEqual(photo["linked_record_id"], str(care_log.pk))

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


class AdminAPIMutationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.member = User.objects.create_user(
            email="member@example.com",
            password="password123",
            name="Member",
        )
        self.family = Family.objects.create(
            name="Mutation Family",
            elder_name="Elder",
            invite_code="888888",
            created_by=self.staff,
        )
        self.staff.family = self.family
        self.staff.save(update_fields=["family"])
        self.member.family = self.family
        self.member.save(update_fields=["family"])

    def audit_model(self):
        return apps.get_model("admin_api", "AdminMutationAuditLog")

    def test_anonymous_user_cannot_create_admin_record(self):
        response = self.client.post("/api/v1/admin/tables/todos/", {}, format="json")

        self.assertEqual(response.status_code, 401)

    def test_non_staff_user_cannot_delete_admin_record(self):
        todo = Todo.objects.create(
            family=self.family,
            title="Delete me",
            assignee=self.member,
            created_by=self.staff,
        )
        self.client.force_authenticate(self.member)

        response = self.client.delete(f"/api/v1/admin/records/todos/{todo.id}/")

        self.assertEqual(response.status_code, 403)

    def test_staff_can_create_allow_listed_record_and_writes_audit_log(self):
        self.client.force_authenticate(self.staff)

        response = self.client.post(
            "/api/v1/admin/tables/todos/",
            {
                "family_id": str(self.family.id),
                "title": "Created from dashboard",
                "assignee_id": str(self.member.id),
                "created_by_id": str(self.staff.id),
                "priority": "high",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        data = response.json()["data"]
        todo = Todo.objects.get(id=data["record"]["id"])
        self.assertEqual(todo.title, "Created from dashboard")
        self.assertEqual(data["raw"]["id"], str(todo.id))
        audit = self.audit_model().objects.get(action="create")
        self.assertEqual(audit.table, "todos")
        self.assertEqual(audit.record_id, str(todo.id))
        self.assertEqual(audit.actor_email, "staff@example.com")


    def test_staff_can_update_allow_listed_record_and_writes_audit_log(self):
        todo = Todo.objects.create(
            family=self.family,
            title="Original title",
            assignee=self.member,
            created_by=self.staff,
            status=Todo.Status.PENDING,
        )
        self.client.force_authenticate(self.staff)

        response = self.client.patch(
            f"/api/v1/admin/records/todos/{todo.id}/",
            {"title": "Updated from dashboard", "status": Todo.Status.COMPLETED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        todo.refresh_from_db()
        self.assertEqual(todo.title, "Updated from dashboard")
        self.assertEqual(todo.status, Todo.Status.COMPLETED)
        self.assertEqual(response.json()["data"]["record"]["title"], "Updated from dashboard")
        audit = self.audit_model().objects.get(action="update")
        self.assertEqual(audit.table, "todos")
        self.assertEqual(audit.record_id, str(todo.id))
        self.assertEqual(audit.metadata["changed_fields"], ["status", "title"])

    def test_staff_can_list_expanded_product_table_records(self):
        medication = Medication.objects.create(
            family=self.family,
            name="Aspirin",
            dosage="100mg",
            frequency=Medication.Frequency.DAILY,
            times=["08:00"],
            start_date="2026-06-01",
            created_by=self.staff,
        )
        self.client.force_authenticate(self.staff)

        response = self.client.get("/api/v1/admin/tables/medications/")

        self.assertEqual(response.status_code, 200)
        ids = {item["id"] for item in response.json()["data"]["results"]}
        self.assertIn(str(medication.id), ids)
    def test_create_rejects_read_only_tables(self):

        self.client.force_authenticate(self.staff)

        response = self.client.post(
            "/api/v1/admin/tables/users/",
            {"email": "new@example.com", "name": "New User"},
            format="json",
        )

        self.assertEqual(response.status_code, 403)

    def test_create_returns_field_level_validation_errors(self):
        self.client.force_authenticate(self.staff)

        response = self.client.post(
            "/api/v1/admin/tables/todos/",
            {"family_id": str(self.family.id)},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        payload = response.json()
        self.assertFalse(payload["success"])
        self.assertEqual(payload["error"]["code"], "validation_error")
        self.assertIn("fields", payload["error"])
        self.assertIn("title", payload["error"]["fields"])

    def test_staff_soft_deletes_record_without_hard_deleting_it(self):
        self.client.force_authenticate(self.staff)
        document = Document.objects.create(
            family=self.family,
            title="Delete document",
            category=Document.Category.MEDICAL,
            file_url="https://storage.carebridge-lab.com/carebridge-storage/docs/delete.pdf",
            file_size=123,
            mime_type="application/pdf",
            uploaded_by=self.staff,
        )

        response = self.client.delete(f"/api/v1/admin/records/documents/{document.id}/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertTrue(data["deleted"])
        self.assertEqual(data["delete_mode"], "soft")
        self.assertTrue(Document.objects.filter(id=document.id).exists())
        self.assertTrue(
            self.audit_model().objects.filter(
                action="delete",
                table="documents",
                record_id=str(document.id),
            ).exists()
        )

        list_response = self.client.get("/api/v1/admin/tables/documents/")
        ids = {item["id"] for item in list_response.json()["data"]["results"]}
        self.assertNotIn(str(document.id), ids)

        detail_response = self.client.get(
            f"/api/v1/admin/records/documents/{document.id}/"
        )
        self.assertEqual(detail_response.status_code, 404)


    def test_update_rejects_read_only_tables(self):
        self.client.force_authenticate(self.staff)

        response = self.client.patch(
            f"/api/v1/admin/records/users/{self.member.id}/",
            {"name": "Changed"},
            format="json",
        )

        self.assertEqual(response.status_code, 403)

    def test_expense_admin_table_allows_update_and_delete(self):
        expense = Expense.objects.create(
            family=self.family,
            recorder=self.staff,
            store_name="Care Store",
            date=timezone.localdate(),
            items=[{"name": "Meal", "category": "food", "total": 120}],
            total_amount=120,
        )
        self.client.force_authenticate(self.staff)

        update_response = self.client.patch(
            f"/api/v1/admin/records/expenses/{expense.id}/",
            {"store_name": "Changed Store"},
            format="json",
        )
        expense.refresh_from_db()

        delete_response = self.client.delete(
            f"/api/v1/admin/records/expenses/{expense.id}/"
        )

        self.assertEqual(update_response.status_code, 200)
        self.assertEqual(expense.store_name, "Changed Store")
        self.assertEqual(delete_response.status_code, 200)
        self.assertTrue(Expense.objects.filter(id=expense.id).exists())

    def test_caregiver_role_staff_can_delete_expense_in_admin_dashboard(self):
        self.staff.role = User.Role.CAREGIVER
        self.staff.save(update_fields=["role"])
        expense = Expense.objects.create(
            family=self.family,
            recorder=self.staff,
            store_name="Care Store",
            date=timezone.localdate(),
            items=[{"name": "Meal", "category": "food", "total": 120}],
            total_amount=120,
        )
        self.client.force_authenticate(self.staff)

        response = self.client.delete(
            f"/api/v1/admin/records/expenses/{expense.id}/"
        )

        self.assertEqual(response.status_code, 200)

    def test_delete_rejects_read_only_tables(self):

        self.client.force_authenticate(self.staff)

        response = self.client.delete(f"/api/v1/admin/records/users/{self.member.id}/")

        self.assertEqual(response.status_code, 403)


class AdminAPIFormSchemaTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.member = User.objects.create_user(
            email="member@example.com",
            password="password123",
            name="Member",
        )
        self.family = Family.objects.create(
            name="Schema Family",
            elder_name="Elder",
            invite_code="121212",
            created_by=self.staff,
        )
        self.client.force_authenticate(self.staff)

    def test_staff_can_read_writable_table_schema(self):
        response = self.client.get("/api/v1/admin/tables/todos/schema/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["table"], "todos")
        self.assertTrue(data["create_allowed"])
        self.assertTrue(data["delete_allowed"])

        fields = {field["name"]: field for field in data["fields"]}
        self.assertEqual(fields["title"]["type"], "string")
        self.assertEqual(fields["title"]["control"], "text")
        self.assertTrue(fields["title"]["required"])
        self.assertEqual(fields["priority"]["control"], "select")
        self.assertIn(
            {"value": "high", "label": "High"},
            fields["priority"]["choices"],
        )
        self.assertEqual(fields["family_id"]["type"], "relation")
        self.assertEqual(fields["family_id"]["relation"]["resource"], "families")
        self.assertEqual(
            fields["family_id"]["relation"]["lookup_url"],
            "/api/v1/admin/lookups/families/",
        )
        self.assertEqual(fields["assignee_id"]["relation"]["resource"], "users")

    def test_read_only_table_schema_is_not_creatable(self):
        response = self.client.get("/api/v1/admin/tables/users/schema/")

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["table"], "users")
        self.assertFalse(data["create_allowed"])
        self.assertFalse(data["delete_allowed"])
        fields = {field["name"]: field for field in data["fields"]}
        self.assertNotIn("password", fields)
        self.assertTrue(all(field["readonly"] for field in fields.values()))

    def test_schema_rejects_unknown_table(self):
        response = self.client.get("/api/v1/admin/tables/not_allowed/schema/")

        self.assertEqual(response.status_code, 404)

    def test_non_staff_user_cannot_read_schema(self):
        self.client.force_authenticate(self.member)

        response = self.client.get("/api/v1/admin/tables/todos/schema/")

        self.assertEqual(response.status_code, 403)

    def test_lookup_users_supports_search_and_safe_pagination(self):
        response = self.client.get(
            "/api/v1/admin/lookups/users/",
            {"search": "mem", "page_size": 200},
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(
            set(data.keys()),
            {"results", "count", "next", "previous", "page", "page_size"},
        )
        self.assertEqual(data["page_size"], 100)
        self.assertEqual(data["results"][0]["id"], str(self.member.id))
        self.assertEqual(data["results"][0]["label"], "Member (member@example.com)")
        self.assertNotIn("password", data["results"][0])

    def test_lookup_families_supports_search(self):
        response = self.client.get(
            "/api/v1/admin/lookups/families/",
            {"search": "Schema"},
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()["data"]["results"][0]
        self.assertEqual(result["id"], str(self.family.id))
        self.assertEqual(result["label"], "Schema Family")

    def test_lookup_rejects_unknown_resource(self):
        response = self.client.get("/api/v1/admin/lookups/storage/")

        self.assertEqual(response.status_code, 404)


class AdminAPIFileMutationTests(TestCase):
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
            name="File Family",
            elder_name="Elder",
            invite_code="999999",
            created_by=self.staff,
        )

    def audit_model(self):
        return apps.get_model("admin_api", "AdminMutationAuditLog")

    @override_settings(AWS_STORAGE_BUCKET_NAME="carebridge-storage")
    @patch("apps.admin_api.views.get_s3_client")
    def test_staff_can_request_preview_presigned_url(self, mock_client):
        mock_client.return_value.head_object.return_value = {
            "ContentType": "application/pdf",
            "ContentLength": 123,
        }
        mock_client.return_value.generate_presigned_url.return_value = (
            "https://storage.example/signed"
        )

        response = self.client.get(
            "/api/v1/admin/files/presign/",
            {
                "bucket": "carebridge-storage",
                "object_key": "docs/report.pdf",
                "mode": "preview",
            },
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["url"], "https://storage.example/signed")
        self.assertEqual(data["expires_in"], 300)
        self.assertEqual(data["disposition"], "inline")
        mock_client.return_value.generate_presigned_url.assert_called_once()
        self.assertTrue(
            self.audit_model().objects.filter(
                action="presign_preview",
                object_key="docs/report.pdf",
            ).exists()
        )

    @override_settings(AWS_STORAGE_BUCKET_NAME="carebridge-storage")
    def test_presign_rejects_path_traversal_object_key(self):
        response = self.client.get(
            "/api/v1/admin/files/presign/",
            {
                "bucket": "carebridge-storage",
                "object_key": "../secrets.env",
                "mode": "preview",
            },
        )

        self.assertEqual(response.status_code, 400)

    @override_settings(AWS_STORAGE_BUCKET_NAME="carebridge-storage")
    @patch("apps.admin_api.views.get_s3_client")
    def test_presign_rejects_unverified_storage_objects(self, mock_client):
        mock_client.return_value.head_object.side_effect = RuntimeError("not found")

        response = self.client.get(
            "/api/v1/admin/files/presign/",
            {
                "bucket": "carebridge-storage",
                "object_key": "docs/missing.pdf",
                "mode": "preview",
            },
        )

        self.assertEqual(response.status_code, 404)
        mock_client.return_value.generate_presigned_url.assert_not_called()

    @override_settings(
        AWS_STORAGE_BUCKET_NAME="carebridge-storage",
        AWS_S3_ENDPOINT_URL="https://storage.carebridge-lab.com",
        AWS_S3_PUBLIC_ENDPOINT_URL="https://storage.carebridge-lab.com",
    )
    @patch("apps.admin_api.views.get_s3_client")
    def test_staff_can_upload_file_with_backend_credentials(self, mock_client):
        uploaded = SimpleUploadedFile(
            "report.pdf",
            b"%PDF-1.4 test",
            content_type="application/pdf",
        )

        response = self.client.post(
            "/api/v1/admin/files/upload/",
            {
                "file": uploaded,
                "table": "documents",
                "family_id": str(self.family.id),
                "purpose": "document",
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        data = response.json()["data"]
        self.assertEqual(data["bucket"], "carebridge-storage")
        self.assertEqual(data["filename"], "report.pdf")
        self.assertEqual(data["content_type"], "application/pdf")
        self.assertTrue(data["object_key"].endswith("/report.pdf"))
        mock_client.return_value.put_object.assert_called_once()
        self.assertTrue(
            self.audit_model().objects.filter(
                action="upload",
                table="documents",
                object_key=data["object_key"],
            ).exists()
        )

    def test_upload_rejects_disallowed_content_type(self):
        uploaded = SimpleUploadedFile(
            "malware.exe",
            b"not really executable",
            content_type="application/x-msdownload",
        )

        response = self.client.post(
            "/api/v1/admin/files/upload/",
            {"file": uploaded, "table": "documents"},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)

    @override_settings(AWS_STORAGE_BUCKET_NAME="carebridge-storage")
    def test_upload_rejects_path_traversal_family_id(self):
        uploaded = SimpleUploadedFile(
            "report.pdf",
            b"%PDF-1.4 test",
            content_type="application/pdf",
        )

        response = self.client.post(
            "/api/v1/admin/files/upload/",
            {
                "file": uploaded,
                "table": "documents",
                "family_id": "../outside",
            },
            format="multipart",
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

    @override_settings(
        CORS_ALLOWED_ORIGINS=["https://shao-zhen.com"],
        CORS_ALLOW_ALL_ORIGINS=False,
    )
    def test_cors_preflight_allows_admin_mutation_methods(self):
        post_response = self.client.options(
            "/api/v1/admin/tables/todos/",
            HTTP_ORIGIN="https://shao-zhen.com",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="POST",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="authorization,content-type,accept",
        )
        delete_response = self.client.options(
            "/api/v1/admin/records/todos/00000000-0000-0000-0000-000000000000/",
            HTTP_ORIGIN="https://shao-zhen.com",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="DELETE",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="authorization,content-type,accept",
        )

        self.assertEqual(post_response.status_code, 200)
        self.assertEqual(delete_response.status_code, 200)
        self.assertEqual(
            post_response["Access-Control-Allow-Origin"],
            "https://shao-zhen.com",
        )
        self.assertEqual(
            delete_response["Access-Control-Allow-Origin"],
            "https://shao-zhen.com",
        )


class AdminAPIRequestLogTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.member = User.objects.create_user(
            email="member@example.com",
            password="password123",
            name="Member",
        )

    def request_log_model(self):
        return apps.get_model("admin_api", "AdminRequestLog")

    def test_successful_api_request_writes_structured_request_log(self):
        self.client.force_authenticate(self.staff)

        response = self.client.get(
            "/api/v1/admin/tables/users/",
            HTTP_X_REQUEST_ID="req-success-1",
            HTTP_USER_AGENT="Dashboard Test",
        )

        self.assertEqual(response.status_code, 200)
        log = self.request_log_model().objects.get(request_id="req-success-1")
        self.assertEqual(log.method, "GET")
        self.assertEqual(log.path, "/api/v1/admin/tables/users/")
        self.assertEqual(log.status_code, 200)
        self.assertEqual(log.user_email, "staff@example.com")
        self.assertTrue(log.is_staff)
        self.assertGreaterEqual(log.duration_ms, 0)
        self.assertNotIn("Bearer", log.metadata)

    def test_failed_api_request_writes_status_and_error_metadata(self):
        self.client.force_authenticate(self.member)

        response = self.client.get(
            "/api/v1/admin/tables/users/",
            HTTP_X_REQUEST_ID="req-failed-1",
        )

        self.assertEqual(response.status_code, 403)
        log = self.request_log_model().objects.get(request_id="req-failed-1")
        self.assertEqual(log.status_code, 403)
        self.assertEqual(log.error_code, "permission_denied")
        self.assertIn("Staff access", log.error_message)

    def test_staff_can_filter_request_logs(self):
        model = self.request_log_model()
        model.objects.create(
            request_id="req-users-ok",
            method="GET",
            path="/api/v1/admin/tables/users/",
            query="search=staff",
            status_code=200,
            duration_ms=12,
            user_email="staff@example.com",
            is_staff=True,
            ip="127.0.0.1",
            user_agent="Dashboard",
        )
        model.objects.create(
            request_id="req-admin-fail",
            method="POST",
            path="/api/v1/admin/tables/todos/",
            query="",
            status_code=400,
            duration_ms=18,
            user_email="staff@example.com",
            is_staff=True,
            ip="127.0.0.1",
            user_agent="Dashboard",
            error_code="validation_error",
            error_message="Invalid request body.",
        )
        self.client.force_authenticate(self.staff)

        response = self.client.get(
            "/api/v1/admin/request-logs/",
            {"status_class": "4xx", "method": "POST", "search": "todos"},
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["results"][0]["request_id"], "req-admin-fail")
        self.assertEqual(data["results"][0]["error_code"], "validation_error")

    def test_request_log_endpoint_rejects_non_staff_user(self):
        self.client.force_authenticate(self.member)

        response = self.client.get("/api/v1/admin/request-logs/")

        self.assertEqual(response.status_code, 403)

class AdminAPIAuditLogTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.staff = User.objects.create_user(
            email="staff@example.com",
            password="password123",
            name="Staff",
            is_staff=True,
        )
        self.member = User.objects.create_user(
            email="member@example.com",
            password="password123",
            name="Member",
        )

    def audit_model(self):
        return apps.get_model("admin_api", "AdminMutationAuditLog")

    def test_staff_can_filter_admin_audit_logs(self):
        model = self.audit_model()
        model.objects.create(
            actor=self.staff,
            actor_email="staff@example.com",
            action="create",
            table="todos",
            record_id="todo-1",
            metadata={"changed_fields": ["title"]},
        )
        model.objects.create(
            actor=self.member,
            actor_email="member@example.com",
            action="delete",
            table="documents",
            record_id="doc-1",
        )
        self.client.force_authenticate(self.staff)

        response = self.client.get(
            "/api/v1/admin/audit-logs/",
            {"table": "todos", "action": "create"},
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()["data"]
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["results"][0]["table"], "todos")
        self.assertEqual(data["results"][0]["action"], "create")
        self.assertEqual(data["results"][0]["actor_email"], "staff@example.com")
        self.assertEqual(data["results"][0]["metadata"], {"changed_fields": ["title"]})

    def test_audit_log_endpoint_rejects_non_staff_user(self):
        self.client.force_authenticate(self.member)

        response = self.client.get("/api/v1/admin/audit-logs/")

        self.assertEqual(response.status_code, 403)
