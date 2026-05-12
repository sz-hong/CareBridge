from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.auth_account.models import User
from apps.care_log.models import CareLog
from apps.family.models import Family
from apps.todo.models import Todo


class TodoAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='todo@example.com',
            password='password123',
            name='Todo User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.assignee = User.objects.create_user(
            email='assignee@example.com',
            password='password123',
            name='Assignee',
            role=User.Role.CAREGIVER,
        )
        self.other_user = User.objects.create_user(
            email='other-todo@example.com',
            password='password123',
            name='Other Todo',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Todo Family',
            elder_name='Elder',
            invite_code='777333',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Todo Family',
            elder_name='Other Elder',
            invite_code='777444',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.assignee.family = self.family
        self.assignee.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def test_list_excludes_other_family_todos(self):
        own = Todo.objects.create(
            family=self.family,
            created_by=self.user,
            assignee=self.assignee,
            title='Own todo',
        )
        Todo.objects.create(
            family=self.other_family,
            created_by=self.other_user,
            assignee=self.other_user,
            title='Other todo',
        )

        response = self.client.get('/api/v1/todos/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_assigns_family_creator_and_assignee(self):
        response = self.client.post(
            '/api/v1/todos/',
            {
                'title': 'Take a walk',
                'assignee_id': str(self.assignee.id),
                'priority': Todo.Priority.HIGH,
                'due_date': timezone.localdate().isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        todo = Todo.objects.get(id=response.json()['data']['id'])
        self.assertEqual(todo.family, self.family)
        self.assertEqual(todo.created_by, self.user)
        self.assertEqual(todo.assignee, self.assignee)
        self.assertEqual(todo.priority, Todo.Priority.HIGH)

    def test_completing_todo_creates_activity_care_log_once(self):
        todo = Todo.objects.create(
            family=self.family,
            created_by=self.user,
            assignee=self.assignee,
            title='Finish stretching',
        )

        response = self.client.put(
            f'/api/v1/todos/{todo.id}/',
            {'status': Todo.Status.COMPLETED},
            format='json',
        )

        todo.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(todo.status, Todo.Status.COMPLETED)
        self.assertIsNotNone(todo.completed_at)
        self.assertIsNotNone(todo.care_log)
        self.assertEqual(todo.care_log.type, CareLog.Type.ACTIVITY)

        response = self.client.put(
            f'/api/v1/todos/{todo.id}/',
            {'status': Todo.Status.COMPLETED},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(CareLog.objects.filter(todos=todo).count(), 1)

    def test_caregiver_cannot_delete_todo(self):
        todo = Todo.objects.create(
            family=self.family,
            created_by=self.user,
            assignee=self.assignee,
            title='Protected todo',
        )
        self.client.force_authenticate(self.assignee)

        response = self.client.delete(f'/api/v1/todos/{todo.id}/')

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()['error']['code'], 'permission_denied')
        self.assertTrue(Todo.objects.filter(id=todo.id).exists())
