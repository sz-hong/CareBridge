"""
Phase 6 — AI Assistant views.

Endpoints:
    POST /ai/chat/          — Conversational AI with Function Calling
    POST /ai/care-analysis/ — Care record analysis report
    POST /ai/handover-report/ — Bilingual handover report generation
    POST /ai/subsidy-form/  — Subsidy form auto-fill
    POST /ai/first-aid/     — First-aid RAG query
"""
import json
import logging
import re
from datetime import timedelta

from django.conf import settings
from django.http import StreamingHttpResponse
from django.utils import timezone
from openai import OpenAI
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.renderers import JSONRenderer
from rest_framework.views import APIView

from core.permissions import CaregiverCannotDelete
from core.responses import error_response, success_response
from .models import AIConversation, FirstAidDocument
from .renderers import EventStreamRenderer
from .serializers import (
    AIChatSerializer,
    CareAnalysisSerializer,
    HandoverReportSerializer,
    SubsidyFormSerializer,
    FirstAidQuerySerializer,
)
from .tools import TOOL_DEFINITIONS, execute_tool

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are CareBridge AI Assistant (照護橋 AI 助理), a bilingual (Traditional Chinese / English) "
    "caregiving expert. You help family members and caregivers monitor and manage elder care.\n\n"
    "Guidelines:\n"
    "- Always respond in the user's language (Traditional Chinese or English).\n"
    "- When asked about health data, medications, care logs, expenses, events, "
    "todos, board requests, leaves, health alerts, medication confirmations, "
    "SOS status, or family member roles, "
    "use the available tools to fetch real data before answering.\n"
    "- Provide actionable advice grounded in the data.\n"
    "- Be empathetic, concise, and professional.\n"
    "- If you detect a medical emergency, advise calling 119 immediately.\n"
    "- Format numbers and dates clearly.\n"
    "- Respond in plain text only. Do not use Markdown syntax."
)


def _plain_text_from_markdown(text, *, strip_edges=True):
    """Remove common Markdown markers from assistant-facing plain text."""
    if not text:
        return ""

    cleaned = text
    cleaned = re.sub(
        r"```(?:[A-Za-z0-9_.+-]+)?\s*([\s\S]*?)```",
        r"\1",
        cleaned,
    )
    cleaned = cleaned.replace("```", "")
    cleaned = re.sub(r"`([^`]*)`", r"\1", cleaned)
    cleaned = cleaned.replace("`", "")

    cleaned = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", cleaned)
    cleaned = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cleaned)
    cleaned = re.sub(r"\]\([^)]+\)", "", cleaned)
    cleaned = cleaned.replace("[", "").replace("]", "")

    cleaned = re.sub(r"(?m)^\s*[-*_]{3,}\s*$", "", cleaned)
    cleaned = re.sub(r"(?m)^\s*[-*+]\s*$", "", cleaned)
    cleaned = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", cleaned)
    cleaned = re.sub(r"(?m)^\s{0,3}>\s?", "", cleaned)
    cleaned = re.sub(r"(?m)^\s*[-*+](?:\s+|(?=[\u4e00-\u9fff]))", "", cleaned)
    cleaned = re.sub(r"(?m)^\s*\d+[.)]\s+", "", cleaned)
    cleaned = re.sub(
        r"(?<!\w)([*_]{1,3})(?=\S)(.*?)(?<=\S)\1(?!\w)",
        r"\2",
        cleaned,
    )
    cleaned = cleaned.replace("*", "")

    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    if strip_edges:
        return cleaned.strip()
    return cleaned


def _accepts_event_stream(request):
    accept_header = request.META.get('HTTP_ACCEPT', '')
    media_types = [
        item.split(';', 1)[0].strip().lower()
        for item in accept_header.split(',')
    ]
    return 'text/event-stream' in media_types


def _get_client():
    api_key = getattr(settings, 'OPENAI_API_KEY', '')
    if not api_key:
        raise RuntimeError('OPENAI_API_KEY is not configured.')
    return OpenAI(api_key=api_key)


def _get_model():
    return getattr(settings, 'OPENAI_MODEL', 'gpt-4o')


def _system_prompt_for_user(user):
    now = timezone.localtime()
    return (
        f"{SYSTEM_PROMPT}\n\n"
        "Current runtime context:\n"
        f"- Current date: {now.date().isoformat()}\n"
        f"- Current local time: {now.strftime('%H:%M:%S')}\n"
        f"- Time zone: {settings.TIME_ZONE}\n"
        f"- User language: {getattr(user, 'language', '') or 'zh-TW'}\n"
        "- Interpret relative dates such as today, tomorrow, and yesterday "
        "using this runtime context before calling tools."
    )


class AIChatView(APIView):
    """
    POST /ai/chat/
    Conversational AI with OpenAI Function Calling.
    Supports SSE streaming via ?stream=true query param.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]
    renderer_classes = [JSONRenderer, EventStreamRenderer]

    def post(self, request):
        serializer = AIChatSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = request.user
        user_message = serializer.validated_data['message']
        conversation_id = serializer.validated_data.get('conversation_id')

        # Load or create conversation
        if conversation_id:
            try:
                conversation = AIConversation.objects.get(
                    id=conversation_id, user=user,
                )
            except AIConversation.DoesNotExist:
                return error_response(
                    code='not_found',
                    message='Conversation not found.',
                    status=404,
                )
        else:
            conversation = AIConversation.objects.create(
                family=user.family,
                user=user,
                messages_history=[],
            )

        # Build messages for OpenAI
        messages = [{"role": "system", "content": _system_prompt_for_user(user)}]
        # Add conversation history (last 20 messages to save tokens)
        history = conversation.messages_history[-20:]
        messages.extend(history)
        messages.append({"role": "user", "content": user_message})

        # Check if streaming requested
        stream_param = request.query_params.get('stream', '').lower()
        if stream_param in {'true', '1', 'yes'}:
            stream = True
        elif stream_param in {'false', '0', 'no'}:
            stream = False
        else:
            stream = _accepts_event_stream(request)

        if stream:
            return self._stream_response(
                messages, conversation, user_message, user,
            )
        else:
            return self._sync_response(
                messages, conversation, user_message, user,
            )

    def _sync_response(self, messages, conversation, user_message, user):
        """Non-streaming response with tool calling loop."""
        client = _get_client()
        model = _get_model()
        total_tokens = 0

        # Tool calling loop (max 5 rounds)
        for _ in range(5):
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                tools=TOOL_DEFINITIONS,
                tool_choice="auto",
                temperature=0.7,
                max_tokens=2048,
            )

            choice = response.choices[0]
            total_tokens += response.usage.total_tokens if response.usage else 0

            if choice.finish_reason == "tool_calls" and choice.message.tool_calls:
                # Append assistant message with tool calls
                messages.append(choice.message.model_dump())

                # Execute each tool call
                for tool_call in choice.message.tool_calls:
                    result = execute_tool(
                        tool_call.function.name,
                        tool_call.function.arguments,
                        user,
                        user_message=user_message,
                    )
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": result,
                    })
            else:
                # Final text response
                reply = _plain_text_from_markdown(choice.message.content or "")
                break
        else:
            reply = "I apologize, I was unable to complete the analysis. Please try again."

        # Save to conversation history
        conversation.messages_history.append(
            {"role": "user", "content": user_message}
        )
        conversation.messages_history.append(
            {"role": "assistant", "content": reply}
        )
        conversation.tokens_used += total_tokens
        conversation.save(update_fields=['messages_history', 'tokens_used', 'updated_at'])

        return success_response(data={
            "conversation_id": str(conversation.id),
            "reply": reply,
            "tokens_used": total_tokens,
        })

    def _stream_response(self, messages, conversation, user_message, user):
        """SSE streaming response with tool calling."""
        client = _get_client()
        model = _get_model()

        def event_stream():
            total_tokens = 0
            raw_full_reply = ""
            streamed_reply = ""

            # First, handle any tool calls (non-streaming)
            for _ in range(5):
                pre_response = client.chat.completions.create(
                    model=model,
                    messages=messages,
                    tools=TOOL_DEFINITIONS,
                    tool_choice="auto",
                    temperature=0.7,
                    max_tokens=2048,
                )
                choice = pre_response.choices[0]
                total_tokens += pre_response.usage.total_tokens if pre_response.usage else 0

                if choice.finish_reason == "tool_calls" and choice.message.tool_calls:
                    messages.append(choice.message.model_dump())
                    for tool_call in choice.message.tool_calls:
                        result = execute_tool(
                            tool_call.function.name,
                            tool_call.function.arguments,
                            user,
                            user_message=user_message,
                        )
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tool_call.id,
                            "content": result,
                        })
                        yield f"data: {json.dumps({'type': 'tool_call', 'tool': tool_call.function.name})}\n\n"
                else:
                    # No more tool calls, break to streaming
                    break

            # Now stream the final response
            stream = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0.7,
                max_tokens=2048,
                stream=True,
            )

            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    raw_content = chunk.choices[0].delta.content
                    raw_full_reply += raw_content
                    plain_reply = _plain_text_from_markdown(raw_full_reply)
                    content = plain_reply[len(streamed_reply):]
                    streamed_reply = plain_reply
                    if content:
                        yield f"data: {json.dumps({'type': 'content', 'text': content})}\n\n"

            # Save conversation
            conversation.messages_history.append(
                {"role": "user", "content": user_message}
            )
            conversation.messages_history.append(
                {
                    "role": "assistant",
                    "content": _plain_text_from_markdown(raw_full_reply),
                }
            )
            conversation.tokens_used += total_tokens
            conversation.save(
                update_fields=['messages_history', 'tokens_used', 'updated_at']
            )

            yield f"data: {json.dumps({'type': 'done', 'conversation_id': str(conversation.id)})}\n\n"

        response = StreamingHttpResponse(
            event_stream(),
            content_type='text/event-stream',
        )
        response['Cache-Control'] = 'no-cache'
        response['X-Accel-Buffering'] = 'no'
        return response


class CareAnalysisView(APIView):
    """
    POST /ai/care-analysis/
    Generates an AI-powered analysis of recent care records.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def post(self, request):
        serializer = CareAnalysisSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        days = serializer.validated_data['days']

        user = request.user
        family = user.family

        # Gather data
        from apps.care_log.models import CareLog
        from apps.health.models import HealthData, HealthAlert
        from apps.medication.models import Medication

        since = timezone.now() - timedelta(days=days)

        care_logs = list(
            CareLog.objects.filter(family=family, timestamp__gte=since)
            .values('type', 'content', 'timestamp')
            .order_by('-timestamp')[:100]
        )

        health_data = list(
            HealthData.objects.filter(family=family, recorded_at__gte=since)
            .values('type', 'value', 'unit', 'recorded_at')
            .order_by('-recorded_at')[:100]
        )

        alerts = list(
            HealthAlert.objects.filter(family=family, created_at__gte=since)
            .values('type', 'value', 'threshold', 'severity', 'created_at')
        )

        medications = list(
            Medication.objects.filter(family=family, is_active=True)
            .values('name', 'dosage', 'frequency', 'time_slots')
        )

        # Build prompt
        data_summary = json.dumps({
            "care_logs": care_logs,
            "health_data": health_data,
            "alerts": alerts,
            "medications": medications,
            "analysis_period_days": days,
        }, default=str, ensure_ascii=False)

        prompt = (
            f"Based on the following {days}-day care data, provide a comprehensive "
            f"care analysis report in Traditional Chinese with English section headers.\n\n"
            f"Include:\n"
            f"1. Overall Health Summary (整體健康摘要)\n"
            f"2. Key Observations (重要觀察)\n"
            f"3. Medication Compliance (用藥遵從度)\n"
            f"4. Risk Factors & Alerts (風險因素與警示)\n"
            f"5. Recommendations (建議事項)\n\n"
            f"Data:\n{data_summary}"
        )

        client = _get_client()
        response = client.chat.completions.create(
            model=_get_model(),
            messages=[
                {"role": "system", "content": (
                    "You are a senior geriatric care analyst. "
                    "Provide detailed, actionable care analysis reports in "
                    "Traditional Chinese (繁體中文) with English section headers."
                )},
                {"role": "user", "content": prompt},
            ],
            temperature=0.5,
            max_tokens=3000,
        )

        reply = response.choices[0].message.content
        tokens_used = response.usage.total_tokens if response.usage else 0

        return success_response(data={
            "analysis": reply,
            "period_days": days,
            "tokens_used": tokens_used,
        })


class HandoverReportView(APIView):
    """
    POST /ai/handover-report/
    Generates a bilingual (zh-TW + English) handover report for caregiver shift changes.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def post(self, request):
        serializer = HandoverReportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        report_date = serializer.validated_data.get('date') or timezone.now().date()

        user = request.user
        family = user.family

        from apps.care_log.models import CareLog
        from apps.medication.models import Medication, MedicationConfirmation
        from apps.health.models import HealthData
        from apps.todo.models import Todo

        # Gather today's data
        care_logs = list(
            CareLog.objects.filter(
                family=family,
                timestamp__date=report_date,
            ).values('type', 'content', 'recorder__name', 'timestamp')
            .order_by('timestamp')
        )

        medications = list(
            Medication.objects.filter(family=family, is_active=True)
            .values('name', 'dosage', 'frequency', 'time_slots')
        )

        confirmations = list(
            MedicationConfirmation.objects.filter(
                medication__family=family,
                confirmed_at__date=report_date,
            ).values(
                'medication__name', 'scheduled_time',
                'confirmed_by__name', 'confirmed_at',
            )
        )

        health = list(
            HealthData.objects.filter(
                family=family,
                recorded_at__date=report_date,
            ).values('type', 'value', 'unit', 'recorded_at')
            .order_by('recorded_at')
        )

        pending_todos = list(
            Todo.objects.filter(
                family=family, status__in=['pending', 'in_progress'],
            ).values('title', 'priority', 'due_date')
        )

        data_summary = json.dumps({
            "date": str(report_date),
            "care_logs": care_logs,
            "medications": medications,
            "medication_confirmations": confirmations,
            "health_data": health,
            "pending_todos": pending_todos,
        }, default=str, ensure_ascii=False)

        prompt = (
            f"Generate a bilingual caregiver handover report for {report_date}.\n\n"
            f"Format: Each section should have BOTH Traditional Chinese and English.\n\n"
            f"Sections:\n"
            f"1. Date & Shift Summary (日期與班次摘要)\n"
            f"2. Health Status Overview (健康狀態概覽)\n"
            f"3. Medication Record (用藥紀錄)\n"
            f"4. Care Activities (照護活動)\n"
            f"5. Pending Tasks (待辦事項)\n"
            f"6. Special Notes & Reminders (特別注意事項)\n\n"
            f"Data:\n{data_summary}"
        )

        client = _get_client()
        response = client.chat.completions.create(
            model=_get_model(),
            messages=[
                {"role": "system", "content": (
                    "You are a caregiving documentation specialist. "
                    "Generate professional bilingual (繁體中文 / English) "
                    "handover reports that are clear, concise, and actionable."
                )},
                {"role": "user", "content": prompt},
            ],
            temperature=0.4,
            max_tokens=3000,
        )

        reply = response.choices[0].message.content
        tokens_used = response.usage.total_tokens if response.usage else 0

        return success_response(data={
            "report": reply,
            "date": str(report_date),
            "tokens_used": tokens_used,
        })


class SubsidyFormView(APIView):
    """
    POST /ai/subsidy-form/
    Auto-fills subsidy application form fields based on the elder's data.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def post(self, request):
        serializer = SubsidyFormSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        form_type = serializer.validated_data['form_type']

        user = request.user
        family = user.family

        from apps.care_log.models import CareLog
        from apps.health.models import HealthData
        from apps.expense.models import Expense
        from django.db.models import Sum, Avg

        # Gather relevant data for form filling
        thirty_days_ago = timezone.now() - timedelta(days=30)

        care_summary = list(
            CareLog.objects.filter(family=family, timestamp__gte=thirty_days_ago)
            .values('type')
            .annotate(count=Sum('id'))
            .order_by('type')
        )

        expense_total = (
            Expense.objects.filter(family=family, date__gte=thirty_days_ago.date())
            .aggregate(total=Sum('amount'))['total'] or 0
        )

        avg_health = list(
            HealthData.objects.filter(family=family, recorded_at__gte=thirty_days_ago)
            .values('type')
            .annotate(avg=Avg('value'))
        )

        data_summary = json.dumps({
            "form_type": form_type,
            "care_activity_summary": care_summary,
            "monthly_expense_total": float(expense_total),
            "average_health_metrics": avg_health,
        }, default=str, ensure_ascii=False)

        form_type_labels = {
            'long_term_care': 'Long-term Care Subsidy (長照補助)',
            'disability': 'Disability Subsidy (身心障礙補助)',
            'respite_care': 'Respite Care Subsidy (喘息服務補助)',
        }

        prompt = (
            f"Based on the following care data, generate pre-filled form fields "
            f"for a {form_type_labels[form_type]} application in Taiwan.\n\n"
            f"Return a JSON object with field names as keys and suggested values.\n"
            f"Include both the field label (in Chinese) and the suggested value.\n\n"
            f"Data:\n{data_summary}"
        )

        client = _get_client()
        response = client.chat.completions.create(
            model=_get_model(),
            messages=[
                {"role": "system", "content": (
                    "You are a Taiwan social welfare specialist. "
                    "Help auto-fill government subsidy application forms "
                    "based on the provided care data. Return valid JSON only."
                )},
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
            max_tokens=2000,
            response_format={"type": "json_object"},
        )

        reply_text = response.choices[0].message.content
        tokens_used = response.usage.total_tokens if response.usage else 0

        try:
            form_fields = json.loads(reply_text)
        except json.JSONDecodeError:
            form_fields = {"raw_response": reply_text}

        return success_response(data={
            "form_type": form_type,
            "form_fields": form_fields,
            "tokens_used": tokens_used,
        })


class FirstAidScenarioListView(APIView):
    """
    GET /ai/first-aid/scenarios/
    Returns static first-aid scenarios for the iOS quick guide.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def get(self, request):
        scenarios = []
        for doc in FirstAidDocument.objects.all():
            steps = [
                line.strip()
                for line in doc.content.splitlines()
                if line.strip()
            ]
            scenarios.append({
                "id": str(doc.id),
                "title": doc.title,
                "icon": "cross.case.fill",
                "steps": steps,
            })

        return success_response(data=scenarios)


class FirstAidView(APIView):
    """
    POST /ai/first-aid/
    RAG-based first-aid query. Searches FirstAidDocument using embeddings,
    then feeds top results to GPT-4o for a tailored response.

    Falls back to direct GPT-4o query if no documents or embeddings are available.
    """
    permission_classes = [IsAuthenticated, CaregiverCannotDelete]

    def post(self, request):
        serializer = FirstAidQuerySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        query = serializer.validated_data['query']

        # Try RAG approach: embed query → find similar docs → augment prompt
        context_docs = self._retrieve_documents(query)

        if context_docs:
            context_text = "\n\n---\n\n".join(
                f"[{doc['title']}] ({doc['source']})\n{doc['content']}"
                for doc in context_docs
            )
            user_prompt = (
                f"Based on the following first-aid reference materials, "
                f"answer the user's question.\n\n"
                f"Reference Materials:\n{context_text}\n\n"
                f"User Question: {query}"
            )
        else:
            user_prompt = (
                f"The user needs first-aid guidance. Answer based on your "
                f"medical knowledge with Taiwan emergency context (119 for ambulance).\n\n"
                f"Question: {query}"
            )

        client = _get_client()
        response = client.chat.completions.create(
            model=_get_model(),
            messages=[
                {"role": "system", "content": (
                    "You are an emergency first-aid assistant for elder care in Taiwan. "
                    "Provide clear, step-by-step first-aid instructions in Traditional Chinese. "
                    "Always remind to call 119 for serious emergencies. "
                    "Include both Chinese and English for critical instructions."
                )},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.3,
            max_tokens=2000,
        )

        reply = response.choices[0].message.content
        tokens_used = response.usage.total_tokens if response.usage else 0

        return success_response(data={
            "answer": reply,
            "sources": [
                {"title": d['title'], "source": d['source']}
                for d in context_docs
            ],
            "tokens_used": tokens_used,
        })

    def _retrieve_documents(self, query, top_k=3):
        """
        Retrieve relevant FirstAidDocuments using OpenAI embeddings.
        Falls back to keyword search if embeddings are not available.
        """
        docs = FirstAidDocument.objects.all()
        if not docs.exists():
            return []

        # Check if any documents have embeddings
        has_embeddings = docs.exclude(embedding__isnull=True).exclude(embedding='').exists()

        if has_embeddings:
            return self._vector_search(query, top_k)
        else:
            return self._keyword_search(query, top_k)

    def _vector_search(self, query, top_k):
        """Search using OpenAI embeddings + cosine similarity."""
        try:
            client = _get_client()
            embedding_model = getattr(
                settings, 'OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small'
            )

            # Get query embedding
            response = client.embeddings.create(
                model=embedding_model,
                input=query,
            )
            query_embedding = response.data[0].embedding

            # For development (SQLite), do in-memory cosine similarity
            # In production with pgvector, use SQL-based similarity search
            import numpy as np

            docs = FirstAidDocument.objects.exclude(
                embedding__isnull=True
            ).exclude(embedding='')

            scored = []
            for doc in docs:
                try:
                    doc_embedding = json.loads(doc.embedding)
                    # Cosine similarity
                    a = np.array(query_embedding)
                    b = np.array(doc_embedding)
                    similarity = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
                    scored.append((similarity, doc))
                except (json.JSONDecodeError, ValueError):
                    continue

            scored.sort(key=lambda x: x[0], reverse=True)

            results = []
            for score, doc in scored[:top_k]:
                results.append({
                    "id": str(doc.id),
                    "title": doc.title,
                    "source": doc.source,
                    "section": doc.section,
                    "content": doc.content[:2000],
                    "relevance_score": score,
                })
            return results

        except Exception:
            logger.exception("Vector search failed, falling back to keyword search")
            return self._keyword_search(query, top_k)

    def _keyword_search(self, query, top_k):
        """Simple keyword-based search fallback."""
        from django.db.models import Q

        words = query.split()
        q_filter = Q()
        for word in words:
            q_filter |= Q(title__icontains=word) | Q(content__icontains=word)

        docs = FirstAidDocument.objects.filter(q_filter)[:top_k]

        results = []
        for doc in docs:
            results.append({
                "id": str(doc.id),
                "title": doc.title,
                "source": doc.source,
                "section": doc.section,
                "content": doc.content[:2000],
            })
        return results
