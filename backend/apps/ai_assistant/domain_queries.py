from datetime import timedelta

from django.db.models import Sum
from django.utils import timezone


def _positive_int(value, default):
    try:
        value = int(value)
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


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
            "content": log.content,
            "recorder": str(log.recorder),
            "timestamp": log.timestamp.isoformat(),
        }
        for log in qs.order_by("-timestamp")[:50]
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
            "instructions": med.instructions or "",
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
            "store_name": exp.store_name or "",
            "category": first_item.get("category", ""),
            "items": exp.items or [],
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
            "title": event.title,
            "type": event.type,
            "start_time": event.start_time.isoformat(),
            "end_time": event.end_time.isoformat() if event.end_time else None,
            "location": event.location or "",
        }
        for event in qs
    ]
    return {"events": results, "count": len(results)}
