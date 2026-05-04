from django.test import SimpleTestCase, override_settings

from core.storage import build_public_url


class StorageURLContractTests(SimpleTestCase):
    @override_settings(
        AWS_STORAGE_BUCKET_NAME='carebridge-storage',
        AWS_S3_ENDPOINT_URL='https://storage.carebridge-lab.com',
    )
    def test_public_minio_endpoint_builds_externally_reachable_url(self):
        self.assertEqual(
            build_public_url('receipts/family-1/receipt.jpg'),
            'https://storage.carebridge-lab.com/carebridge-storage/receipts/family-1/receipt.jpg',
        )

    @override_settings(
        AWS_STORAGE_BUCKET_NAME='carebridge-storage',
        AWS_S3_ENDPOINT_URL='https://storage.carebridge-lab.com/',
    )
    def test_public_minio_endpoint_ignores_trailing_slash(self):
        self.assertEqual(
            build_public_url('receipts/family-1/receipt.jpg'),
            'https://storage.carebridge-lab.com/carebridge-storage/receipts/family-1/receipt.jpg',
        )
