from django.test import TestCase
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.family.models import Family


class FamilyAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='family@example.com',
            password='password123',
            name='Family User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-family@example.com',
            password='password123',
            name='Other Family',
            role=User.Role.FAMILY_MEMBER,
        )
        self.joiner = User.objects.create_user(
            email='joiner@example.com',
            password='password123',
            name='Joiner',
            role=User.Role.CAREGIVER,
        )
        self.family = Family.objects.create(
            name='Primary Family',
            elder_name='Elder',
            invite_code='111222',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Family',
            elder_name='Other Elder',
            invite_code='333444',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.is_primary = True
        self.user.save(update_fields=['family', 'is_primary'])
        self.other_user.family = self.other_family
        self.other_user.is_primary = True
        self.other_user.save(update_fields=['family', 'is_primary'])
        self.client.force_authenticate(self.user)

    def test_list_returns_only_authenticated_users_family(self):
        response = self.client.get('/api/v1/families/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(self.family.id)})

    def test_retrieve_other_family_returns_not_found(self):
        response = self.client.get(f'/api/v1/families/{self.other_family.id}/')

        self.assertEqual(response.status_code, 404)

    def test_create_assigns_creator_to_new_primary_family_member(self):
        new_user = User.objects.create_user(
            email='new-family@example.com',
            password='password123',
            name='New Family',
            role=User.Role.CAREGIVER,
        )
        self.client.force_authenticate(new_user)

        response = self.client.post(
            '/api/v1/families/',
            {
                'name': 'Created Family',
                'elder_name': 'Created Elder',
            },
            format='json',
        )

        new_user.refresh_from_db()
        family = Family.objects.get(id=response.json()['data']['id'])
        self.assertEqual(response.status_code, 201)
        self.assertEqual(family.created_by, new_user)
        self.assertEqual(new_user.family, family)
        self.assertTrue(new_user.is_primary)
        self.assertEqual(new_user.role, User.Role.FAMILY_MEMBER)

    def test_join_allows_invite_code_for_target_family(self):
        self.client.force_authenticate(self.joiner)

        response = self.client.post(
            f'/api/v1/families/{self.family.id}/join/',
            {'invite_code': self.family.invite_code},
            format='json',
        )

        self.joiner.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.joiner.family, self.family)
        self.assertFalse(self.joiner.is_primary)
