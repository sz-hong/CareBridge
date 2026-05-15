import re

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from unittest.mock import patch

from apps.auth_account.models import User
from apps.chat.models import Chat, ChatMember, Message
from apps.family.models import Family


class ChatAPIEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email='chat@example.com',
            password='password123',
            name='Chat User',
            role=User.Role.FAMILY_MEMBER,
        )
        self.member = User.objects.create_user(
            email='chat-member@example.com',
            password='password123',
            name='Chat Member',
            role=User.Role.CAREGIVER,
        )
        self.other_user = User.objects.create_user(
            email='other-chat@example.com',
            password='password123',
            name='Other Chat',
            role=User.Role.FAMILY_MEMBER,
        )
        self.family = Family.objects.create(
            name='Chat Family',
            elder_name='Elder',
            invite_code='737373',
            created_by=self.user,
        )
        self.other_family = Family.objects.create(
            name='Other Chat Family',
            elder_name='Other Elder',
            invite_code='474747',
            created_by=self.other_user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])
        self.member.family = self.family
        self.member.save(update_fields=['family'])
        self.other_user.family = self.other_family
        self.other_user.save(update_fields=['family'])
        self.client.force_authenticate(self.user)

    def create_chat(self, members=None, **overrides):
        defaults = {
            'type': Chat.Type.GROUP,
            'name': 'Family Chat',
            'family': self.family,
        }
        defaults.update(overrides)
        chat = Chat.objects.create(**defaults)
        for user in members or [self.user, self.member]:
            ChatMember.objects.create(chat=chat, user=user)
        return chat

    def test_list_returns_only_chats_current_user_belongs_to(self):
        own = self.create_chat(name='Own chat')
        self.create_chat(name='Member only chat', members=[self.member])
        self.create_chat(
            name='Other family chat',
            family=self.other_family,
            members=[self.other_user],
        )

        response = self.client.get('/api/v1/chats/')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.json()['data']}
        self.assertEqual(ids, {str(own.id)})

    def test_create_rejects_other_family_id(self):
        response = self.client.post(
            '/api/v1/chats/',
            {
                'type': Chat.Type.GROUP,
                'name': 'Cross family chat',
                'family_id': str(self.other_family.id),
                'member_ids': [str(self.other_user.id)],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 403)
        self.assertFalse(response.json()['success'])
        self.assertEqual(response.json()['error']['code'], 'permission_denied')
        self.assertFalse(Chat.objects.filter(name='Cross family chat').exists())

    def test_create_rejects_members_outside_family(self):
        response = self.client.post(
            '/api/v1/chats/',
            {
                'type': Chat.Type.GROUP,
                'name': 'Invalid member chat',
                'family_id': str(self.family.id),
                'member_ids': [str(self.member.id), str(self.other_user.id)],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.json()['success'])
        self.assertEqual(response.json()['error']['code'], 'invalid_members')
        self.assertFalse(Chat.objects.filter(name='Invalid member chat').exists())

    def test_create_adds_creator_and_requested_family_members(self):
        response = self.client.post(
            '/api/v1/chats/',
            {
                'type': Chat.Type.GROUP,
                'name': 'Care team',
                'family_id': str(self.family.id),
                'member_ids': [str(self.member.id)],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        chat = Chat.objects.get(id=response.json()['data']['id'])
        member_ids = set(
            ChatMember.objects.filter(chat=chat).values_list('user_id', flat=True)
        )
        self.assertEqual(chat.family, self.family)
        self.assertEqual(member_ids, {self.user.id, self.member.id})

    @patch('apps.notification.tasks.send_notification_task.delay')
    @patch('apps.chat.views.ChatViewSet._broadcast_message')
    @patch('core.translation.translate_text')
    def test_send_text_message_creates_message_for_chat_member(
        self, translate_text, _broadcast_message, _delay,
    ):
        def fake_translate(masked_text, _source, _targets):
            self.assertNotIn('Amlodipine', masked_text)
            self.assertNotIn('5mg', masked_text)
            placeholders = re.findall(r'__CB_PROTECTED_\d+__', masked_text)
            self.assertGreaterEqual(len(placeholders), 2)
            return {'id': f'Halo tentang {placeholders[0]} {placeholders[1]}'}

        translate_text.side_effect = fake_translate
        chat = self.create_chat()

        response = self.client.post(
            f'/api/v1/chats/{chat.id}/messages/',
            {'type': Message.Type.TEXT, 'content': 'Hello about Amlodipine 5mg'},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        message = Message.objects.get(id=response.json()['data']['id'])
        self.assertEqual(message.chat, chat)
        self.assertEqual(message.sender, self.user)
        self.assertEqual(message.type, Message.Type.TEXT)
        self.assertEqual(message.message_type, Message.MessageType.TEXT)
        self.assertEqual(message.content, 'Hello about Amlodipine 5mg')
        self.assertEqual(
            message.translations['id'],
            'Halo tentang Amlodipine 5mg',
        )

    def test_message_history_returns_recent_page_in_chronological_order(self):
        chat = self.create_chat()
        old_message = Message.objects.create(
            chat=chat,
            sender=self.member,
            type=Message.Type.TEXT,
            content='Older',
        )
        new_message = Message.objects.create(
            chat=chat,
            sender=self.user,
            type=Message.Type.TEXT,
            content='Newer',
        )
        Message.objects.filter(id=old_message.id).update(
            sent_at=timezone.now() - timezone.timedelta(minutes=2),
        )
        Message.objects.filter(id=new_message.id).update(
            sent_at=timezone.now() - timezone.timedelta(minutes=1),
        )

        response = self.client.get(f'/api/v1/chats/{chat.id}/messages/')

        self.assertEqual(response.status_code, 200)
        ids = [item['id'] for item in response.json()['data']]
        self.assertEqual(ids[-2:], [str(old_message.id), str(new_message.id)])
