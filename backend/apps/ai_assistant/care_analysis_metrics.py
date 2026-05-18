from collections import defaultdict
from decimal import Decimal, InvalidOperation


METRIC_DEFINITIONS = {
    "heart_rate": ("心率", "bpm"),
    "blood_oxygen": ("血氧", "%"),
    "step_count": ("步數", "steps"),
    "active_energy": ("活動熱量", "kcal"),
    "blood_pressure_systolic": ("收縮壓", "mmHg"),
    "blood_pressure_diastolic": ("舒張壓", "mmHg"),
    "blood_sugar": ("血糖", "mmol/L"),
    "temperature": ("體溫", "°C"),
    "weight": ("體重", "kg"),
}

CARE_LOG_VITAL_KEYS = {
    "blood_pressure_systolic",
    "blood_pressure_diastolic",
    "blood_sugar",
    "temperature",
    "weight",
}


def build_health_metrics_summary(health_data, vital_care_logs):
    points_by_metric = defaultdict(list)

    for row in health_data:
        metric_type = row.get("type")
        value = _decimal_or_none(row.get("value"))
        if metric_type not in METRIC_DEFINITIONS or value is None:
            continue
        points_by_metric[metric_type].append({
            "value": value,
            "unit": row.get("unit") or METRIC_DEFINITIONS[metric_type][1],
            "recorded_at": row.get("recorded_at"),
        })

    for row in vital_care_logs:
        content = row.get("content") or {}
        if not isinstance(content, dict):
            continue
        recorded_at = row.get("timestamp")
        for metric_type in CARE_LOG_VITAL_KEYS:
            value = _decimal_or_none(content.get(metric_type))
            if value is None:
                continue
            points_by_metric[metric_type].append({
                "value": value,
                "unit": METRIC_DEFINITIONS[metric_type][1],
                "recorded_at": recorded_at,
            })

    metrics = []
    for metric_type in METRIC_DEFINITIONS:
        points = sorted(
            points_by_metric.get(metric_type, []),
            key=lambda point: str(point["recorded_at"] or ""),
        )
        if not points:
            continue
        metrics.append(_summarize_metric(metric_type, points))

    return {
        "metrics": metrics,
        "text": render_health_metrics_summary(metrics),
    }


def render_health_metrics_summary(metrics):
    lines = ["身體數據摘要"]
    if not metrics:
        lines.append("本期間無可用身體數據。")
        lines.append("已檢查來源：HealthData、照護紀錄生命徵象。")
        return "\n".join(lines)

    for metric in metrics:
        lines.append(
            f"{metric['label']}："
            f"筆數 {metric['count']}，"
            f"最新值 {_format_value(metric['latest_value'])} {metric['unit']}，"
            f"最高值 {_format_value(metric['max_value'])} {metric['unit']}，"
            f"最低值 {_format_value(metric['min_value'])} {metric['unit']}，"
            f"平均值 {_format_value(metric['avg_value'])} {metric['unit']}，"
            f"第一筆 {_format_value(metric['first_value'])} {metric['unit']}，"
            f"最後一筆 {_format_value(metric['last_value'])} {metric['unit']}，"
            f"變化量 {_format_delta(metric['change'])} {metric['unit']}，"
            f"趨勢 {metric['trend']}，"
            f"最新時間 {_format_timestamp(metric['latest_time'])}。"
        )
    return "\n".join(lines)


def _summarize_metric(metric_type, points):
    label, default_unit = METRIC_DEFINITIONS[metric_type]
    values = [point["value"] for point in points]
    first_value = values[0]
    last_value = values[-1]
    change = last_value - first_value
    return {
        "type": metric_type,
        "label": label,
        "unit": points[-1].get("unit") or default_unit,
        "count": len(values),
        "latest_value": last_value,
        "max_value": max(values),
        "min_value": min(values),
        "avg_value": sum(values) / Decimal(len(values)),
        "first_value": first_value,
        "last_value": last_value,
        "change": change,
        "trend": _trend_label(change),
        "latest_time": points[-1].get("recorded_at"),
    }


def _decimal_or_none(value):
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None


def _trend_label(change):
    if change > 0:
        return "上升"
    if change < 0:
        return "下降"
    return "持平"


def _format_value(value):
    normalized = value.quantize(Decimal("0.1"))
    if normalized == normalized.to_integral_value():
        return str(normalized.to_integral_value())
    return str(normalized.normalize())


def _format_delta(value):
    formatted = _format_value(abs(value))
    if value > 0:
        return f"+{formatted}"
    if value < 0:
        return f"-{formatted}"
    return formatted


def _format_timestamp(value):
    if not value:
        return "未知"
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)
