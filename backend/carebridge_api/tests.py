import os
from unittest.mock import patch

from django.test import SimpleTestCase


class SettingsContractTests(SimpleTestCase):
    def test_env_list_trims_values_and_drops_empty_items(self):
        from carebridge_api.settings import base

        with patch.dict(
            os.environ,
            {'CAREBRIDGE_TEST_CSV': ' api.carebridge-lab.com, , localhost ,127.0.0.1, '},
        ):
            self.assertEqual(
                base.env_list('CAREBRIDGE_TEST_CSV'),
                ['api.carebridge-lab.com', 'localhost', '127.0.0.1'],
            )

    def test_production_trusts_cloudflare_forwarded_proto_header(self):
        from carebridge_api.settings import production

        self.assertEqual(
            production.SECURE_PROXY_SSL_HEADER,
            ('HTTP_X_FORWARDED_PROTO', 'https'),
        )
