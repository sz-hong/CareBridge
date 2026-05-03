from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.expense.models import Expense
from apps.family.models import Family


class ExpenseAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='expense@example.com',
            password='password123',
            name='Expense User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.other_user = User.objects.create_user(
            email='other-expense@example.com',
            password='password123',
            name='Other Expense',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Expense Family',
            elder_name='Elder',
            invite_code='222111',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Expense Family',
            elder_name='Other Elder',
            invite_code='222222',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_expense(self, **overrides):
        defaults = {
            'family': self.family,
            'recorder': self.user,
            'store_name': 'Care Store',
            'date': timezone.localdate(),
            'items': [{'name': 'Meal', 'category': 'food', 'total': 120}],
            'total_amount': 120,
            'status': Expense.Status.COMPLETED,
        }
        defaults.update(overrides)
        return Expense.objects.create(**defaults)

    def test_list_filters_by_family_and_date_range(self):
        today = timezone.localdate()
        own = self.create_expense(date=today)
        self.create_expense(date=today - timezone.timedelta(days=10))
        self.create_expense(
            family=self.other_family,
            recorder=self.other_user,
            date=today,
        )

        response = self.client.get(
            '/api/v1/expenses/',
            {
                'date_from': today.isoformat(),
                'date_to': today.isoformat(),
            },
        )

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_assigns_family_recorder_and_completed_status(self):
        response = self.client.post(
            '/api/v1/expenses/',
            {
                'store_name': 'Pharmacy',
                'date': timezone.localdate().isoformat(),
                'items': [{'name': 'Medicine', 'category': 'medical', 'total': 350}],
                'total_amount': '350.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        expense = Expense.objects.get(id=response.json()['data']['id'])
        self.assertEqual(expense.family, self.family)
        self.assertEqual(expense.recorder, self.user)
        self.assertEqual(expense.status, Expense.Status.COMPLETED)

    def test_scan_creates_processing_expense(self):
        response = self.client.post(
            '/api/v1/expenses/scan/',
            {'image_url': 'https://example.com/receipt.jpg'},
            format='json',
        )

        self.assertEqual(response.status_code, 202)
        expense = Expense.objects.get(id=response.json()['data']['id'])
        self.assertEqual(expense.family, self.family)
        self.assertEqual(expense.recorder, self.user)
        self.assertEqual(expense.status, Expense.Status.PROCESSING)
        self.assertEqual(expense.total_amount, 0)
        self.assertTrue(expense.scan_id)

    def test_monthly_summary_uses_completed_current_month_family_expenses(self):
        today = timezone.localdate()
        self.create_expense(
            date=today,
            total_amount=300,
            items=[
                {'name': 'Medicine', 'category': 'medical', 'total': 200},
                {'name': 'Meal', 'category': 'food', 'total': 100},
            ],
        )
        self.create_expense(
            date=today,
            total_amount=50,
            status=Expense.Status.PROCESSING,
            items=[{'name': 'Pending', 'category': 'food', 'total': 50}],
        )
        self.create_expense(
            family=self.other_family,
            recorder=self.other_user,
            date=today,
            total_amount=999,
        )

        response = self.client.get('/api/v1/expenses/monthly/')

        data = response.json()['data']
        self.assertEqual(response.status_code, 200)
        self.assertEqual(data['monthly_total'], 300.0)
        self.assertEqual(
            data['category_breakdown'],
            [
                {'category': 'medical', 'percentage': 66.7},
                {'category': 'food', 'percentage': 33.3},
            ],
        )
