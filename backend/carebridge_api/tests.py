import importlib
import os
import sys
from unittest.mock import patch

from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase


SETTINGS_MODULES = [
    'carebridge_api.settings.base',
    'carebridge_api.settings.development',
    'carebridge_api.settings.production',
]


class SecretKeySettingsTests(SimpleTestCase):
    def setUp(self):
        self.original_modules = {
            name: sys.modules.get(name)
            for name in SETTINGS_MODULES
        }

    def tearDown(self):
        for name in SETTINGS_MODULES:
            if self.original_modules[name] is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = self.original_modules[name]

    def import_settings(self, module_name):
        for name in SETTINGS_MODULES:
            sys.modules.pop(name, None)
        return importlib.import_module(module_name)

    def test_production_requires_secret_key_environment_variable(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesMessage(
                ImproperlyConfigured,
                'DJANGO_SECRET_KEY environment variable is required in production',
            ):
                self.import_settings('carebridge_api.settings.production')

    def test_development_uses_dev_only_secret_key_when_env_is_missing(self):
        with patch.dict(os.environ, {}, clear=True):
            settings = self.import_settings('carebridge_api.settings.development')

        self.assertEqual(
            settings.SECRET_KEY,
            'django-insecure-dev-only-do-not-use-in-prod',
        )
