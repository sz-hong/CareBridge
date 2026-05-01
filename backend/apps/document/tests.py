from django.test import TestCase
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.document.models import Document
from apps.family.models import Family


class DocumentAPIContractTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='docs@example.com',
            password='password123',
            name='Docs User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Docs Family',
            elder_name='Elder',
            invite_code='444444',
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def test_delete_returns_success_envelope_that_mobile_can_decode(self):
        document = Document.objects.create(
            family=self.family,
            uploaded_by=self.user,
            title='Insurance',
            category=Document.Category.INSURANCE,
            file_url='https://example.com/doc.pdf',
            file_size=128,
            mime_type='application/pdf',
        )

        response = self.client.delete(f'/api/v1/documents/{document.id}/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'success': True, 'data': {}})
        self.assertFalse(Document.objects.filter(id=document.id).exists())
