import logging

from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from apps.chat.models import Chat, ChatMember, Message
from apps.chat.serializers import (
    ChatSerializer,
    CreateChatSerializer,
    MessageSerializer,
    SendMessageSerializer,
)
from core.pagination import StandardPagination
from core.responses import success_response
from core.translation import SUPPORTED_LANGUAGES, translate_text

logger = logging.getLogger(__name__)


class ChatViewSet(ModelViewSet):
    """
    CRUD for chats the current user belongs to, plus a nested
    ``messages`` action for history retrieval and sending.
    """

    serializer_class = ChatSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = StandardPagination
    lookup_field = 'pk'

    # ── querysets ───────────────────────────────────────────────
    def get_queryset(self):
        return (
            Chat.objects
            .filter(members__user=self.request.user)
            .prefetch_related('members__user', 'messages')
            .distinct()
        )

    # ── list ───────────────────────────────────────────────────
    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return success_response(
                data=serializer.data,
                meta={
                    'count': self.paginator.page.paginator.count,
                    'page': self.paginator.page.number,
                    'page_size': self.paginator.page_size,
                },
            )
        serializer = self.get_serializer(queryset, many=True)
        return success_response(data=serializer.data)

    # ── create ─────────────────────────────────────────────────
    def create(self, request, *args, **kwargs):
        ser = CreateChatSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        chat = Chat.objects.create(
            type=ser.validated_data['type'],
            name=ser.validated_data.get('name', ''),
            family_id=ser.validated_data['family_id'],
        )

        # Add creator as a member
        ChatMember.objects.create(chat=chat, user=request.user)

        # Add other requested members (skip if creator is already included)
        for uid in ser.validated_data['member_ids']:
            if uid != request.user.id:
                ChatMember.objects.get_or_create(chat=chat, user_id=uid)

        out = ChatSerializer(chat, context={'request': request})
        return success_response(data=out.data, status=201)

    # ── retrieve ───────────────────────────────────────────────
    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        return success_response(data=serializer.data)

    # ── update / partial_update ────────────────────────────────
    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return success_response(data=serializer.data)

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)

    # ── destroy ────────────────────────────────────────────────
    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(status=204)

    # ── messages action ────────────────────────────────────────
    @action(detail=True, methods=['get', 'post'], url_path='messages')
    def messages(self, request, pk=None):
        chat = self.get_object()

        if request.method == 'GET':
            return self._list_messages(request, chat)
        return self._send_message(request, chat)

    # --- helpers ---------------------------------------------------

    def _list_messages(self, request, chat):
        qs = Message.objects.filter(chat=chat).select_related('sender')
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = MessageSerializer(page, many=True)
            return success_response(
                data=serializer.data,
                meta={
                    'count': self.paginator.page.paginator.count,
                    'page': self.paginator.page.number,
                    'page_size': self.paginator.page_size,
                },
            )
        serializer = MessageSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def _send_message(self, request, chat):
        ser = SendMessageSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        message = Message.objects.create(
            chat=chat,
            sender=request.user,
            type=ser.validated_data.get('type', 'text'),
            content=ser.validated_data.get('content', ''),
            image_url=ser.validated_data.get('image_url', ''),
        )

        # Attempt translation for text messages
        if message.type == 'text' and message.content:
            self._translate_message(message, request.user)

        # Phase 7: Notify other chat members of new message
        try:
            from apps.notification.tasks import send_notification_task
            sender_name = request.user.name or request.user.email
            member_ids = (
                ChatMember.objects.filter(chat=chat)
                .exclude(user=request.user)
                .values_list('user_id', flat=True)
            )
            content_preview = (message.content or '')[:80]
            for uid in member_ids:
                send_notification_task.delay(
                    user_id=str(uid),
                    type='chat_message',
                    title=f'New message from {sender_name}',
                    body=content_preview,
                    data={
                        'chat_id': str(chat.id),
                        'message_id': str(message.id),
                    },
                )
        except Exception:
            logger.warning('Failed to send chat message notification', exc_info=True)

        out = MessageSerializer(message)
        return success_response(data=out.data, status=201)

    @staticmethod
    def _translate_message(message, sender):
        """
        Translate the message content into all supported languages
        except the sender's own language.  Failures are logged but
        never bubble up to the caller.
        """
        source_lang = getattr(sender, 'language', None)
        if not source_lang or source_lang not in SUPPORTED_LANGUAGES:
            return

        target_langs = [
            lang for lang in SUPPORTED_LANGUAGES if lang != source_lang
        ]
        if not target_langs:
            return

        try:
            translations = translate_text(
                message.content, source_lang, target_langs,
            )
            # Include the original text keyed by source language
            translations[source_lang] = message.content
            message.translations = translations
            message.save(update_fields=['translations'])
        except Exception:
            logger.exception(
                'Translation failed for message %s', message.id,
            )
