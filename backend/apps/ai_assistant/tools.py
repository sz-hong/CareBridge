"""
OpenAI Function Calling tool definitions for the AI assistant.

These tools allow GPT-4o to query backend data on behalf of the user
during a conversation (e.g. "How is grandma's blood pressure this week?").
"""
import json
import logging
from datetime import timedelta

from django.utils import timezone

logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------
# Tool definitions (OpenAI function-calling schema)
# --------------------------------------------------------------------------

TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "query_health_data",
            "description": (
                "Query the elder's health data. Returns recent vital signs "
                "such as heart rate, blood pressure, blood oxygen, temperature, "
                "and step count."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "data_type": {
                        "type": "string",
                        "enum": [
                            "heart_rate", "blood_pressure_systolic",
                            "blood_pressure_diastolic", "blood_oxygen",
                            "temperature", "step_count",
                        ],
                        "description": "Type of health data to query. Omit to get all types.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 7).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_care_logs",
            "description": (
                "Query recent care log entries (meals, medication, vitals, "
                "activity, incidents)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "log_type": {
                        "type": "string",
                        "enum": [
                            "meal", "medication", "vital_sign",
                            "activity", "incident", "other",
                        ],
                        "description": "Filter by log type. Omit for all types.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days (default 7).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_medications",
            "description": "Query the elder's current medications and schedules.",
            "parameters": {
                "type": "object",
                "properties": {
                    "active_only": {
                        "type": "boolean",
                        "description": "If true, only return active medications.",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_expenses",
            "description": "Query care-related expenses and monthly totals.",
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {
                        "type": "integer",
                        "description": "Number of past days (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_events",
            "description": "Query upcoming calendar events (appointments, leave, etc.).",
            "parameters": {
                "type": "object",
                "properties": {
                    "days_ahead": {
                        "type": "integer",
                        "description": "Number of days ahead to look (default 14).",
                    },
                },
                "required": [],
            },
        },
    },
]

# --------------------------------------------------------------------------
# Tool execution functions
# --------------------------------------------------------------------------


def execute_tool(tool_name, arguments, user):
    """Execute a tool call and return the result as a string."""
    try:
        args = json.loads(arguments) if isinstance(arguments, str) else arguments
    except json.JSONDecodeError:
        args = {}

    handler = TOOL_HANDLERS.get(tool_name)
    if not handler:
        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    try:
        result = handler(args, user)
        return json.dumps(result, default=str, ensure_ascii=False)
    except Exception as e:
        logger.exception("Tool execution error: %s", tool_name)
        return json.dumps({"error": str(e)})


def _query_health_data(args, user):
    from apps.health.models import HealthData

    family = user.family
    days = args.get("days", 7)
    since = timezone.now() - timedelta(days=days)
    qs = HealthData.objects.filter(family=family, recorded_at__gte=since)

    data_type = args.get("data_type")
    if data_type:
        qs = qs.filter(type=data_type)

    qs = qs.order_by("-recorded_at")[:50]
    results = []
    for d in qs:
        results.append({
            "type": d.type,
            "value": float(d.value),
            "unit": d.unit,
            "recorded_at": d.recorded_at.isoformat(),
        })
    return {"health_data": results, "count": len(results)}


def _query_care_logs(args, user):
    from apps.care_log.models import CareLog

    family = user.family
    days = args.get("days", 7)
    since = timezone.now() - timedelta(days=days)
    qs = CareLog.objects.filter(family=family, timestamp__gte=since)

    log_type = args.get("log_type")
    if log_type:
        qs = qs.filter(type=log_type)

    qs = qs.order_by("-timestamp")[:50]
    results = []
    for log in qs:
        results.append({
            "type": log.type,
            "content": log.content,
            "recorder": str(log.recorder),
            "timestamp": log.timestamp.isoformat(),
        })
    return {"care_logs": results, "count": len(results)}


def _query_medications(args, user):
    from apps.medication.models import Medication

    family = user.family
    qs = Medication.objects.filter(family=family)

    active_only = args.get("active_only", True)
    if active_only:
        qs = qs.filter(is_active=True)

    results = []
    for med in qs:
        results.append({
            "name": med.name,
            "dosage": med.dosage,
            "frequency": med.frequency,
            "time_slots": med.time_slots,
            "instructions": med.instructions or "",
            "is_active": med.is_active,
        })
    return {"medications": results, "count": len(results)}


def _query_expenses(args, user):
    from apps.expense.models import Expense
    from django.db.models import Sum

    family = user.family
    days = args.get("days", 30)
    since = timezone.now() - timedelta(days=days)
    qs = Expense.objects.filter(family=family, date__gte=since.date())

    total = qs.aggregate(total=Sum("amount"))["total"] or 0
    results = []
    for exp in qs.order_by("-date")[:30]:
        results.append({
            "category": exp.category,
            "amount": float(exp.amount),
            "description": exp.description,
            "date": exp.date.isoformat(),
        })
    return {"expenses": results, "total": float(total), "count": len(results)}


def _query_events(args, user):
    from apps.calendar_event.models import Event

    family = user.family
    days_ahead = args.get("days_ahead", 14)
    now = timezone.now()
    until = now + timedelta(days=days_ahead)
    qs = Event.objects.filter(
        family=family,
        start_time__gte=now,
        start_time__lte=until,
    ).order_by("start_time")[:30]

    results = []
    for event in qs:
        results.append({
            "title": event.title,
            "type": event.type,
            "start_time": event.start_time.isoformat(),
            "end_time": event.end_time.isoformat() if event.end_time else None,
            "location": event.location or "",
        })
    return {"events": results, "count": len(results)}


TOOL_HANDLERS = {
    "query_health_data": _query_health_data,
    "query_care_logs": _query_care_logs,
    "query_medications": _query_medications,
    "query_expenses": _query_expenses,
    "query_events": _query_events,
}
