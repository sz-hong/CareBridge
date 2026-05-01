from uuid import uuid4

from django.test import SimpleTestCase
from django.urls import Resolver404, resolve


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
