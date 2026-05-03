from django.test import TestCase
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.board.models import BoardRequest
from apps.family.models import Family


class BoardRequestAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='board@example.com',
            password='password123',
            name='Board User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.reviewer = User.objects.create_user(
            email='board-reviewer@example.com',
            password='password123',
            name='Board Reviewer',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-board@example.com',
            password='password123',
            name='Other Board',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Board Family',
            elder_name='Elder',
            invite_code='919191',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Board Family',
            elder_name='Other Elder',
            invite_code='828282',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.reviewer.family = self.family
        self.reviewer.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_request(self, **overrides):
        defaults = {
            'family': self.family,
            'requester': self.user,
            'category': BoardRequest.Category.FOOD,
            'items': [{'name': 'Banana', 'quantity': 2}],
            'note': 'For breakfast',
            'status': BoardRequest.Status.PENDING,
        }
        defaults.update(overrides)
        return BoardRequest.objects.create(**defaults)

    def test_list_filters_by_family_and_status(self):
        own = self.create_request(status=BoardRequest.Status.PENDING)
        self.create_request(status=BoardRequest.Status.APPROVED)
        self.create_request(
            family=self.other_family,
            requester=self.other_user,
            status=BoardRequest.Status.PENDING,
        )

        response = self.client.get(
            '/api/v1/board/',
            {'status': BoardRequest.Status.PENDING},
        )

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_assigns_family_and_requester(self):
        response = self.client.post(
            '/api/v1/board/',
            {
                'category': BoardRequest.Category.MEDICAL,
                'items': [{'name': 'Blood pressure monitor', 'quantity': 1}],
                'note': 'Need a spare device',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        board_request = BoardRequest.objects.get(id=response.json()['data']['id'])
        self.assertEqual(board_request.family, self.family)
        self.assertEqual(board_request.requester, self.user)
        self.assertEqual(board_request.status, BoardRequest.Status.PENDING)

    def test_update_status_sets_reply_and_reviewer(self):
        board_request = self.create_request()
        self.client.force_authenticate(self.reviewer)

        response = self.client.patch(
            f'/api/v1/board/{board_request.id}/status/',
            {
                'status': BoardRequest.Status.APPROVED,
                'reply': 'Approved for purchase',
            },
            format='json',
        )

        board_request.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(board_request.status, BoardRequest.Status.APPROVED)
        self.assertEqual(board_request.reply, 'Approved for purchase')
        self.assertEqual(board_request.reviewed_by, self.reviewer)

    def test_invalid_status_returns_error_envelope(self):
        board_request = self.create_request()

        response = self.client.patch(
            f'/api/v1/board/{board_request.id}/status/',
            {'status': 'unknown'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.json()['success'])
        self.assertEqual(response.json()['error']['code'], 'invalid_status')
