import re
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings

from core.deidentification import (
    GoogleDLPDeidentificationClient,
    get_deidentification_client,
    prepare_text_for_gpt,
)
from core.pii_patterns import CUSTOM_REGEX_INFO_TYPES
from core.storage import build_public_url
from core.translation import (
    SUPPORTED_LANGUAGES,
    protected_entity_map,
    translate_for_user,
)


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


class TranslationProtectedEntityTests(SimpleTestCase):
    def test_protected_entity_map_returns_original_for_every_language(self):
        result = protected_entity_map('Amlodipine 5mg')

        self.assertEqual(set(result), set(SUPPORTED_LANGUAGES))
        self.assertTrue(
            all(value == 'Amlodipine 5mg' for value in result.values())
        )

    @patch('core.translation.translate_text')
    def test_mixed_text_masks_and_restores_protected_spans(self, translate_text):
        def fake_translate(masked_text, _source, _targets):
            self.assertNotIn('Amlodipine', masked_text)
            self.assertNotIn('08:00', masked_text)
            placeholders = re.findall(r'__CB_PROTECTED_\d+__', masked_text)
            self.assertGreaterEqual(len(placeholders), 2)
            return {
                'id': (
                    f'Tolong minum {placeholders[0]} setelah makan '
                    f'pada {placeholders[1]}'
                )
            }

        translate_text.side_effect = fake_translate

        result = translate_for_user(
            'Please take Amlodipine after meals at 08:00',
            source_lang='zh-TW',
            target_langs=['id'],
            mode='mixed_text',
            protected_terms=['Amlodipine'],
        )

        self.assertEqual(
            result['id'],
            'Tolong minum Amlodipine setelah makan pada 08:00',
        )

    @patch('core.translation.translate_text')
    def test_mixed_text_falls_back_when_translation_drops_placeholder(
        self, translate_text,
    ):
        text = 'Take Amlodipine 5mg after meals'
        translate_text.return_value = {'id': 'Minum obat setelah makan'}

        result = translate_for_user(
            text,
            source_lang='zh-TW',
            target_langs=['id'],
            mode='mixed_text',
            protected_terms=['Amlodipine'],
        )

        self.assertEqual(result['id'], text)


class MockDeidentificationClientTests(SimpleTestCase):
    def test_custom_regex_patterns_are_google_dlp_re2_compatible(self):
        unsupported_tokens = ('(?<', '(?=', '(?!')

        for name, pattern in CUSTOM_REGEX_INFO_TYPES.items():
            for token in unsupported_tokens:
                self.assertNotIn(token, pattern, msg=f'{name} uses {token}')

    @override_settings(DLP_PROVIDER='mock')
    def test_mock_client_redacts_common_identifiers(self):
        client = get_deidentification_client()

        result = client.deidentify_text(
            'Email amy@example.com, phone 0912-345-678, card 4111 1111 1111 1111.'
        )

        self.assertNotIn('amy@example.com', result.text)
        self.assertNotIn('0912-345-678', result.text)
        self.assertNotIn('4111 1111 1111 1111', result.text)
        self.assertIn('[EMAIL_ADDRESS]', result.text)
        self.assertIn('[TAIWAN_PHONE_NUMBER]', result.text)
        self.assertIn('[CREDIT_CARD_NUMBER]', result.text)
        self.assertGreaterEqual(len(result.findings), 3)
        self.assertNotIn('quote', result.findings_as_dicts()[0])
        self.assertIn('quote_length', result.findings_as_dicts()[0])

    @override_settings(DLP_PROVIDER='mock')
    def test_prepare_text_for_gpt_returns_deidentified_text(self):
        output = prepare_text_for_gpt('Send to amy@example.com')

        self.assertEqual(output, 'Send to [EMAIL_ADDRESS]')

    @override_settings(
        AWS_STORAGE_BUCKET_NAME='carebridge-storage',
        AWS_S3_ENDPOINT_URL='https://storage.carebridge-lab.com/',
    )
    def test_public_minio_endpoint_ignores_trailing_slash(self):
        self.assertEqual(
            build_public_url('receipts/family-1/receipt.jpg'),
            'https://storage.carebridge-lab.com/carebridge-storage/receipts/family-1/receipt.jpg',
        )


class GoogleDLPDeidentificationClientTests(SimpleTestCase):
    @override_settings(
        GOOGLE_CLOUD_PROJECT='carebridge-test',
        DLP_PROVIDER='google_dlp',
    )
    def test_image_redaction_configs_do_not_duplicate_info_types(self):
        class FakeDLPClient:
            request = None

            def redact_image(self, request):
                self.request = request
                return SimpleNamespace(
                    redacted_image=b'redacted',
                    inspect_result=SimpleNamespace(findings=[]),
                )

        client = GoogleDLPDeidentificationClient()
        fake_client = FakeDLPClient()
        client._client = lambda: fake_client

        client.redact_image(b'raw-image', 'image/jpeg')

        names = [
            config['info_type']['name']
            for config in fake_client.request['image_redaction_configs']
        ]
        self.assertEqual(len(names), len(set(names)))
        self.assertIn('EMAIL_ADDRESS', names)
        self.assertIn('CREDIT_CARD_NUMBER', names)
        self.assertIn('TAIWAN_PHONE_NUMBER', names)
