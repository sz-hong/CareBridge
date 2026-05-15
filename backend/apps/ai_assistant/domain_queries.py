import logging
from datetime import timedelta

from django.db.models import Sum
from django.utils.dateparse import parse_date
from django.utils import timezone

from core.deidentification import prepare_text_for_gpt


logger = logging.getLogger(__name__)

SENSITIVE_JSON_KEYS = {
    "raw_image_key",
    "raw_file_key",
    "redacted_image_key",
    "redacted_file_key",
    "image_url",
    "file_url",
    "photo_url",
    "device_id",
    "device_token",
    "email",
    "phone",
    "avatar_url",
    "location",
    "notified_members",
}


def _positive_int(value, default):
    try:
        value = int(value)
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def _safe_text(value):
    if value is None:
        return ""
    if not isinstance(value, str):
        value = str(value)
    if not value:
        return ""
    try:
        return prepare_text_for_gpt(value)
    except Exception:
        logger.exception("Failed to deidentify AI tool text")
        return "[redaction_failed]"


def _safe_json(value):
    if isinstance(value, dict):
        return {
            key: _safe_json(item)
            for key, item in value.items()
            if str(key).lower() not in SENSITIVE_JSON_KEYS
        }
    if isinstance(value, list):
        return [_safe_json(item) for item in value]
    if isinstance(value, str):
        return _safe_text(value)
    return value


def _user_name(user):
    return getattr(user, "name", None) or ""


def _date_range(days):
    return timezone.now() - timedelta(days=_positive_int(days, 30))


def _valid_date(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value
    if not isinstance(value, str):
        value = str(value)
    return parse_date(value)


def query_health_data(args, user):
    from apps.health.models import HealthData

    family = getattr(user, "family", None)
    if family is None:
        return {"health_data": [], "count": 0}

    days = _positive_int(args.get("days"), 7)
    since = timezone.now() - timedelta(days=days)
    qs = HealthData.objects.filter(family=family, recorded_at__gte=since)

    data_type = args.get("data_type")
    if data_type:
        qs = qs.filter(type=data_type)

    results = [
        {
            "type": item.type,
            "value": float(item.value),
            "unit": item.unit,
            "recorded_at": item.recorded_at.isoformat(),
        }
        for item in qs.order_by("-recorded_at")[:50]
    ]
    return {"health_data": results, "count": len(results)}


def query_care_logs(args, user):
    from apps.care_log.models import CareLog

    family = getattr(user, "family", None)
    if family is None:
        return {"care_logs": [], "count": 0}

    days = _positive_int(args.get("days"), 7)
    since = timezone.now() - timedelta(days=days)
    qs = CareLog.objects.filter(family=family, timestamp__gte=since)

    log_type = args.get("log_type")
    if log_type:
        qs = qs.filter(type=log_type)

    results = [
        {
            "type": log.type,
            "content": _safe_json(log.content),
            "recorder": _user_name(log.recorder),
            "timestamp": log.timestamp.isoformat(),
        }
        for log in qs.select_related("recorder").order_by("-timestamp")[:50]
    ]
    return {"care_logs": results, "count": len(results)}


def query_medications(args, user):
    from apps.medication.models import Medication

    family = getattr(user, "family", None)
    if family is None:
        return {"medications": [], "count": 0}

    qs = Medication.objects.filter(family=family)
    if args.get("active_only", True):
        qs = qs.filter(is_active=True)

    results = [
        {
            "name": med.name,
            "dosage": med.dosage,
            "frequency": med.frequency,
            "times": med.times,
            "time_slots": med.times,
            "instructions": _safe_text(med.instructions or ""),
            "is_active": med.is_active,
        }
        for med in qs.order_by("name")
    ]
    return {"medications": results, "count": len(results)}


def query_expenses(args, user):
    from apps.expense.models import Expense

    family = getattr(user, "family", None)
    if family is None:
        return {"expenses": [], "total": 0.0, "count": 0}

    days = _positive_int(args.get("days"), 30)
    since = timezone.now() - timedelta(days=days)
    qs = Expense.objects.filter(family=family, date__gte=since.date())

    total = qs.aggregate(total=Sum("total_amount"))["total"] or 0
    results = []
    for exp in qs.order_by("-date")[:30]:
        first_item = (exp.items or [{}])[0] if isinstance(exp.items, list) else {}
        results.append({
            "store_name": _safe_text(exp.store_name or ""),
            "category": first_item.get("category", ""),
            "items": _safe_json(exp.items or []),
            "total_amount": float(exp.total_amount),
            "amount": float(exp.total_amount),
            "date": exp.date.isoformat(),
            "status": exp.status,
        })
    return {"expenses": results, "total": float(total), "count": len(results)}


def query_events(args, user):
    from apps.calendar_event.models import Event

    family = getattr(user, "family", None)
    if family is None:
        return {"events": [], "count": 0}

    days_ahead = _positive_int(args.get("days_ahead"), 14)
    now = timezone.now()
    until = now + timedelta(days=days_ahead)
    qs = Event.objects.filter(
        family=family,
        start_time__gte=now,
        start_time__lte=until,
    ).order_by("start_time")[:30]

    results = [
        {
            "title": _safe_text(event.title),
            "type": event.type,
            "start_time": event.start_time.isoformat(),
            "end_time": event.end_time.isoformat() if event.end_time else None,
            "location": _safe_text(event.location or ""),
        }
        for event in qs
    ]
    return {"events": results, "count": len(results)}


def query_todos(args, user):
    from apps.todo.models import Todo

    family = getattr(user, "family", None)
    if family is None:
        return {"todos": [], "count": 0}

    qs = Todo.objects.filter(family=family)
    status = args.get("status")
    if status:
        qs = qs.filter(status=status)
    priority = args.get("priority")
    if priority:
        qs = qs.filter(priority=priority)
    due_date = _valid_date(args.get("due_date"))
    if due_date:
        qs = qs.filter(due_date=due_date)
    date_from = _valid_date(args.get("date_from"))
    if date_from:
        qs = qs.filter(due_date__gte=date_from)
    date_to = _valid_date(args.get("date_to"))
    if date_to:
        qs = qs.filter(due_date__lte=date_to)
    days_ahead = args.get("days_ahead")
    if days_ahead is not None:
        until = timezone.localdate() + timedelta(days=_positive_int(days_ahead, 30))
        qs = qs.filter(due_date__isnull=False, due_date__lte=until)

    results = [
        {
            "title": _safe_text(todo.title),
            "assignee": _user_name(todo.assignee),
            "priority": todo.priority,
            "status": todo.status,
            "due_date": todo.due_date.isoformat() if todo.due_date else None,
            "completed_at": todo.completed_at.isoformat() if todo.completed_at else None,
            "created_by": _user_name(todo.created_by),
            "created_at": todo.created_at.isoformat(),
        }
        for todo in (
            qs.select_related("assignee", "created_by")
            .order_by("-created_at")[:50]
        )
    ]
    return {"todos": results, "count": len(results)}


def query_board_requests(args, user):
    from apps.board.models import BoardRequest

    family = getattr(user, "family", None)
    if family is None:
        return {"board_requests": [], "count": 0}

    qs = BoardRequest.objects.filter(
        family=family,
        created_at__gte=_date_range(args.get("days")),
    )
    status = args.get("status")
    if status:
        qs = qs.filter(status=status)
    category = args.get("category")
    if category:
        qs = qs.filter(category=category)

    results = [
        {
            "category": request.category,
            "items": _safe_json(request.items),
            "note": _safe_text(request.note or ""),
            "note_translated": _safe_json(request.note_translated or ""),
            "status": request.status,
            "reply": _safe_text(request.reply or ""),
            "requester": _user_name(request.requester),
            "reviewed_by": _user_name(request.reviewed_by),
            "created_at": request.created_at.isoformat(),
            "updated_at": request.updated_at.isoformat(),
        }
        for request in (
            qs.select_related("requester", "reviewed_by")
            .order_by("-created_at")[:50]
        )
    ]
    return {"board_requests": results, "count": len(results)}


def query_leaves(args, user):
    from apps.leave.models import Leave

    family = getattr(user, "family", None)
    if family is None:
        return {"leaves": [], "count": 0}

    qs = Leave.objects.filter(
        family=family,
        created_at__gte=_date_range(args.get("days")),
    )
    status = args.get("status")
    if status:
        qs = qs.filter(status=status)

    results = []
    for leave in (
        qs.select_related("applicant", "reviewed_by")
        .prefetch_related("votes")
        .order_by("-created_at")[:50]
    ):
        results.append({
            "type": leave.type,
            "start_date": leave.start_date.isoformat(),
            "end_date": leave.end_date.isoformat(),
            "days": leave.days,
            "reason": _safe_text(leave.reason),
            "reason_translated": _safe_text(leave.reason_translated or ""),
            "status": leave.status,
            "reply": _safe_text(leave.reply or ""),
            "applicant": _user_name(leave.applicant),
            "reviewed_by": _user_name(leave.reviewed_by),
            "reviewed_at": leave.reviewed_at.isoformat() if leave.reviewed_at else None,
            "votes": [
                {
                    "member_name": _safe_text(vote.member_name),
                    "is_available": vote.is_available,
                    "voted_at": vote.voted_at.isoformat(),
                }
                for vote in leave.votes.all()
            ],
            "created_at": leave.created_at.isoformat(),
        })
    return {"leaves": results, "count": len(results)}


def query_health_alerts(args, user):
    from apps.health.models import HealthAlert

    family = getattr(user, "family", None)
    if family is None:
        return {"health_alerts": [], "count": 0}

    qs = HealthAlert.objects.filter(
        family=family,
        created_at__gte=_date_range(args.get("days")),
    )
    severity = args.get("severity")
    if severity:
        qs = qs.filter(severity=severity)
    if "acknowledged" in args:
        qs = qs.filter(acknowledged_at__isnull=not bool(args.get("acknowledged")))

    results = [
        {
            "type": alert.type,
            "value": float(alert.value),
            "threshold": float(alert.threshold),
            "severity": alert.severity,
            "acknowledged": alert.acknowledged_at is not None,
            "acknowledged_by": _user_name(alert.acknowledged_by),
            "acknowledged_at": (
                alert.acknowledged_at.isoformat()
                if alert.acknowledged_at
                else None
            ),
            "recorded_at": alert.recorded_at.isoformat(),
            "created_at": alert.created_at.isoformat(),
        }
        for alert in qs.select_related("acknowledged_by").order_by("-created_at")[:50]
    ]
    return {"health_alerts": results, "count": len(results)}


def query_medication_confirmations(args, user):
    from apps.medication.models import MedicationConfirmation

    family = getattr(user, "family", None)
    if family is None:
        return {"medication_confirmations": [], "count": 0}

    days = _positive_int(args.get("days"), 7)
    since = timezone.now() - timedelta(days=days)
    qs = MedicationConfirmation.objects.filter(
        medication__family=family,
        confirmed_at__gte=since,
    )

    results = [
        {
            "medication_name": confirmation.medication.name,
            "scheduled_time": confirmation.scheduled_time,
            "note": _safe_text(confirmation.note or ""),
            "confirmed_by": _user_name(confirmation.confirmed_by),
            "confirmed_at": confirmation.confirmed_at.isoformat(),
        }
        for confirmation in (
            qs.select_related("medication", "confirmed_by")
            .order_by("-confirmed_at")[:50]
        )
    ]
    return {"medication_confirmations": results, "count": len(results)}


def query_sos_status(args, user):
    from apps.sos.models import SOSRecord

    family = getattr(user, "family", None)
    if family is None:
        return {"sos_records": [], "count": 0}

    qs = SOSRecord.objects.filter(
        family=family,
        triggered_at__gte=_date_range(args.get("days")),
    )
    status = args.get("status")
    if status:
        qs = qs.filter(status=status)

    results = [
        {
            "triggered_by": _user_name(record.triggered_by),
            "situation": _safe_text(record.situation or ""),
            "auto_call_119": record.auto_call_119,
            "notified_count": len(record.notified_members or []),
            "status": record.status,
            "triggered_at": record.triggered_at.isoformat(),
            "resolved_at": record.resolved_at.isoformat() if record.resolved_at else None,
        }
        for record in qs.select_related("triggered_by").order_by("-triggered_at")[:30]
    ]
    return {"sos_records": results, "count": len(results)}


def query_family_members(args, user):
    from apps.auth_account.models import User

    family = getattr(user, "family", None)
    if family is None:
        return {"family_members": [], "count": 0}

    qs = User.objects.filter(family=family).order_by("role", "name")
    results = [
        {
            "name": member.name,
            "role": member.role,
            "language": member.language,
            "is_primary": member.is_primary,
        }
        for member in qs[:50]
    ]
    return {"family_members": results, "count": len(results)}
