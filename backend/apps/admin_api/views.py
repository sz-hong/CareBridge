import re
from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.paginator import EmptyPage, Paginator
from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.views import APIView

from apps.auth_account.models import User
from apps.board.models import BoardRequest
from apps.calendar_event.models import Event
from apps.care_log.models import CareLog
from apps.document.models import Document
from apps.expense.models import Expense
from apps.family.models import Family
from apps.health.models import HealthAlert, HealthAlertThreshold, HealthData
from apps.medication.models import MedicationConfirmation
from apps.todo.models import Todo
from core.responses import error_response, success_response
from core.storage import _get_s3_client, extract_key_from_url


MAX_PAGE_SIZE = 100
DEFAULT_PAGE_SIZE = 20
MAX_ACTIVITY_LIMIT = 100
DEFAULT_ACTIVITY_LIMIT = 12
MAX_LOG_LINES = 500
DEFAULT_LOG_LINES = 100

SENSITIVE_FIELD_NAMES = {
    'password',
    'last_login',
    'user_permissions',
    'groups',
}
SENSITIVE_FIELD_MARKERS = (
    'token',
    'secret',
    'credential',
    'access_key',
    'private_key',
    'apns',
)

URL_FIELD_NAMES = (
    'avatar_url',
    'file_url',
    'image_url',
    'photo_url',
)


@dataclass(frozen=True)
class TableConfig:
    model: object
    search_fields: tuple[str, ...] = ()
    date_fields: tuple[str, ...] = ('updated_at', 'created_at')
    actor_fields: tuple[str, ...] = ()


TABLES = {
    'users': TableConfig(
        model=User,
        search_fields=('email', 'name', 'phone'),
        actor_fields=(),
    ),
    'families': TableConfig(
        model=Family,
        search_fields=('name', 'elder_name', 'invite_code'),
        actor_fields=('created_by',),
    ),
    'care_logs': TableConfig(
        model=CareLog,
        search_fields=('type', 'recorder__email', 'recorder__name'),
        date_fields=('created_at', 'timestamp'),
        actor_fields=('recorder',),
    ),
    'board_requests': TableConfig(
        model=BoardRequest,
        search_fields=(
            'category',
            'status',
            'note',
            'requester__email',
            'requester__name',
        ),
        actor_fields=('requester', 'reviewed_by'),
    ),
    'todos': TableConfig(
        model=Todo,
        search_fields=('title', 'priority', 'status', 'assignee__email', 'assignee__name'),
        actor_fields=('created_by', 'assignee'),
    ),
    'events': TableConfig(
        model=Event,
        search_fields=('title', 'type', 'location', 'note'),
        date_fields=('created_at', 'start_time'),
        actor_fields=('created_by',),
    ),
    'health_data': TableConfig(
        model=HealthData,
        search_fields=('type', 'unit', 'device_id'),
        date_fields=('created_at', 'recorded_at'),
    ),
    'health_alerts': TableConfig(
        model=HealthAlert,
        search_fields=('type', 'severity'),
        date_fields=('created_at', 'recorded_at', 'acknowledged_at'),
        actor_fields=('acknowledged_by',),
    ),
    'health_thresholds': TableConfig(
        model=HealthAlertThreshold,
        search_fields=('family__name',),
        date_fields=('updated_at',),
        actor_fields=('updated_by',),
    ),
    'expenses': TableConfig(
        model=Expense,
        search_fields=('store_name', 'status', 'recorder__email', 'recorder__name'),
        date_fields=('updated_at', 'created_at', 'date'),
        actor_fields=('recorder',),
    ),
    'documents': TableConfig(
        model=Document,
        search_fields=('title', 'category', 'mime_type', 'uploaded_by__email'),
        actor_fields=('uploaded_by',),
    ),
}

EXTRA_FILE_MODELS = {
    'medication_confirmations': MedicationConfirmation,
}

LOG_STREAMS = {
    'api-errors': 'api-errors.log',
    'runtime': 'runtime.log',
}


class IsActiveStaff(BasePermission):
    message = 'Staff access is required.'

    def has_permission(self, request, view):
        user = getattr(request, 'user', None)
        return bool(
            user
            and user.is_authenticated
            and getattr(user, 'is_active', False)
            and getattr(user, 'is_staff', False)
        )


class StaffReadOnlyAPIView(APIView):
    permission_classes = [IsAuthenticated, IsActiveStaff]
    http_method_names = ['get', 'options']


def get_s3_client():
    return _get_s3_client()


def get_table_config(table):
    config = TABLES.get(table)
    if not config:
        return None
    return config


def model_has_field(model, field_name):
    try:
        model._meta.get_field(field_name)
        return True
    except Exception:
        return False


def parse_positive_int(value, default, maximum):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    if parsed < 1:
        return default
    return min(parsed, maximum)


def parse_lower_bound(value):
    if not value:
        return None
    parsed = parse_datetime(value)
    if parsed is not None:
        return parsed
    parsed_date = parse_date(value)
    if parsed_date is not None:
        return parsed_date
    return None


def normalize_value(value):
    if value is None:
        return None
    if isinstance(value, (UUID,)):
        return str(value)
    if hasattr(value, 'isoformat'):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, list):
        return [normalize_value(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize_value(item) for key, item in value.items()}
    return value


def is_sensitive_field(field_name):
    lowered = field_name.lower()
    return lowered in SENSITIVE_FIELD_NAMES or any(
        marker in lowered for marker in SENSITIVE_FIELD_MARKERS
    )


def serialize_instance(instance):
    data = {}
    for field in instance._meta.fields:
        if is_sensitive_field(field.name):
            continue
        if field.is_relation and field.many_to_one:
            key = f'{field.name}_id'
            value = getattr(instance, field.attname)
        else:
            key = field.name
            value = getattr(instance, field.name)
        data[key] = normalize_value(value)
    return data


def get_queryset(config):
    queryset = config.model.objects.all()
    related_fields = [
        field.name
        for field in config.model._meta.fields
        if field.is_relation and field.many_to_one
    ]
    if related_fields:
        queryset = queryset.select_related(*related_fields)
    return queryset


def apply_search(queryset, config, search):
    if not search:
        return queryset
    query = Q()
    for field_name in config.search_fields:
        query |= Q(**{f'{field_name}__icontains': search})
    if not query:
        return queryset
    return queryset.filter(query)


def apply_date_filters(queryset, config, params):
    date_from = parse_lower_bound(params.get('date_from'))
    date_to = parse_lower_bound(params.get('date_to'))
    if date_from is None and date_to is None:
        return queryset

    available_fields = [
        field_name
        for field_name in config.date_fields
        if model_has_field(config.model, field_name)
    ]
    if not available_fields:
        return queryset

    query = Q()
    for field_name in available_fields:
        field_query = Q()
        if date_from is not None:
            field_query &= Q(**{f'{field_name}__gte': date_from})
        if date_to is not None:
            field_query &= Q(**{f'{field_name}__lte': date_to})
        query |= field_query
    return queryset.filter(query)


def order_queryset(queryset, config):
    for field_name in ('updated_at', 'created_at', 'recorded_at', 'timestamp', 'date'):
        if model_has_field(config.model, field_name):
            return queryset.order_by(f'-{field_name}')
    return queryset.order_by('-pk')


def paginate_queryset(queryset, request):
    page_size = parse_positive_int(
        request.query_params.get('page_size'),
        DEFAULT_PAGE_SIZE,
        MAX_PAGE_SIZE,
    )
    requested_page = parse_positive_int(request.query_params.get('page'), 1, 10**9)
    paginator = Paginator(queryset, page_size)
    try:
        page = paginator.page(requested_page)
    except EmptyPage:
        page = paginator.page(paginator.num_pages or 1)

    return {
        'results': [serialize_instance(item) for item in page.object_list],
        'count': paginator.count,
        'next': page.next_page_number() if page.has_next() else None,
        'previous': page.previous_page_number() if page.has_previous() else None,
        'page': page.number,
        'page_size': page_size,
    }


def get_count_since(model, field_name, since):
    if not model_has_field(model, field_name):
        return 0
    return model.objects.filter(**{f'{field_name}__gte': since}).count()


def get_actor(instance, config):
    for field_name in config.actor_fields:
        actor = getattr(instance, field_name, None)
        if actor:
            return getattr(actor, 'email', None) or getattr(actor, 'name', None) or str(actor)
    return None


def timestamp_for(instance, action):
    field_name = 'updated_at' if action == 'updated' else 'created_at'
    value = getattr(instance, field_name, None)
    if value is not None:
        return value
    for fallback in ('recorded_at', 'timestamp', 'date'):
        value = getattr(instance, fallback, None)
        if value is not None:
            return value
    return None


def build_activity_item(table, config, instance, action):
    timestamp = timestamp_for(instance, action)
    return {
        'id': f'{table}:{instance.pk}:{action}:{normalize_value(timestamp)}',
        'table': table,
        'record_id': str(instance.pk),
        'action': action,
        'actor': get_actor(instance, config),
        'created_at': normalize_value(timestamp),
    }


def related_files_for_instance(table, instance):
    files = []
    bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
    for field_name in URL_FIELD_NAMES:
        if not hasattr(instance, field_name):
            continue
        url = getattr(instance, field_name)
        key = extract_key_from_url(url)
        if not key:
            continue
        files.append(
            {
                'bucket': bucket,
                'object_key': key,
                'size': None,
                'last_modified': None,
                'content_type': None,
                'linked_table': table,
                'linked_record_id': str(instance.pk),
                'orphan': False,
            }
        )
    return files


def collect_linked_file_map():
    linked = {}
    model_items = {
        **{table: config.model for table, config in TABLES.items()},
        **EXTRA_FILE_MODELS,
    }
    for table, model in model_items.items():
        field_names = [
            field.name
            for field in model._meta.fields
            if field.name in URL_FIELD_NAMES
        ]
        if not field_names:
            continue
        for instance in model.objects.all():
            for field_name in field_names:
                key = extract_key_from_url(getattr(instance, field_name))
                if key and key not in linked:
                    linked[key] = {
                        'linked_table': table,
                        'linked_record_id': str(instance.pk),
                    }
    return linked


def safe_prefix(prefix):
    if not prefix:
        return ''
    if '..' in prefix or '\\' in prefix:
        return None
    return prefix.lstrip('/')


def read_log_stream(stream, lines):
    filename = LOG_STREAMS[stream]
    path = settings.BASE_DIR / 'logs' / filename
    if not path.exists():
        return []
    raw_lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    return [parse_log_line(line) for line in raw_lines[-lines:]]


def parse_log_line(line):
    match = re.match(
        r'^(?P<timestamp>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:,\d+)?)\s+'
        r'(?:(?P<logger>[\w.]+)\s+)?(?P<level>DEBUG|INFO|WARNING|ERROR|CRITICAL)\s+'
        r'(?P<message>.*)$',
        line,
    )
    if not match:
        return {
            'timestamp': None,
            'level': 'INFO',
            'message': line,
            'request_id': None,
        }
    return {
        'timestamp': match.group('timestamp').replace(',', '.'),
        'level': match.group('level'),
        'message': match.group('message'),
        'request_id': None,
    }


class OverviewView(StaffReadOnlyAPIView):
    def get(self, request):
        since = timezone.now() - timedelta(days=1)
        tables = []
        for table, config in TABLES.items():
            tables.append(
                {
                    'table': table,
                    'count': config.model.objects.count(),
                    'created_24h': get_count_since(config.model, 'created_at', since),
                    'updated_24h': get_count_since(config.model, 'updated_at', since),
                }
            )

        alerts = []
        critical_alerts = HealthAlert.objects.filter(
            severity=HealthAlert.Severity.CRITICAL,
            acknowledged_at__isnull=True,
        ).count()
        if critical_alerts:
            alerts.append(
                {
                    'severity': 'critical',
                    'title': 'Unacknowledged critical health alerts',
                    'count': critical_alerts,
                }
            )

        if not getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None):
            alerts.append(
                {
                    'severity': 'warning',
                    'title': 'Storage bucket is not configured',
                    'count': 1,
                }
            )
        elif not getattr(settings, 'AWS_ACCESS_KEY_ID', None) or not getattr(
            settings, 'AWS_SECRET_ACCESS_KEY', None
        ):
            alerts.append(
                {
                    'severity': 'warning',
                    'title': 'Storage credentials are not configured',
                    'count': 1,
                }
            )
        else:
            try:
                get_s3_client().list_objects_v2(
                    Bucket=settings.AWS_STORAGE_BUCKET_NAME,
                    MaxKeys=1,
                )
            except Exception:
                alerts.append(
                    {
                        'severity': 'warning',
                        'title': 'Storage listing failed',
                        'count': 1,
                    }
                )

        data = {
            'kpis': [
                {
                    'label': 'Users',
                    'value': User.objects.count(),
                    'delta_24h': get_count_since(User, 'created_at', since),
                },
                {
                    'label': 'Families',
                    'value': Family.objects.count(),
                    'delta_24h': get_count_since(Family, 'created_at', since),
                },
            ],
            'tables': tables,
            'alerts': alerts,
        }
        return success_response(data=data)


class ActivityView(StaffReadOnlyAPIView):
    def get(self, request):
        limit = parse_positive_int(
            request.query_params.get('limit'),
            DEFAULT_ACTIVITY_LIMIT,
            MAX_ACTIVITY_LIMIT,
        )
        since = parse_lower_bound(request.query_params.get('since'))
        cursor = parse_lower_bound(request.query_params.get('cursor'))

        items = []
        for table, config in TABLES.items():
            for action, field_name in (('created', 'created_at'), ('updated', 'updated_at')):
                if not model_has_field(config.model, field_name):
                    continue
                queryset = get_queryset(config)
                if since is not None:
                    queryset = queryset.filter(**{f'{field_name}__gte': since})
                if cursor is not None:
                    queryset = queryset.filter(**{f'{field_name}__lt': cursor})
                for instance in queryset.order_by(f'-{field_name}')[:limit]:
                    items.append(build_activity_item(table, config, instance, action))

        items.sort(key=lambda item: item['created_at'] or '', reverse=True)
        sliced = items[:limit]
        next_cursor = sliced[-1]['created_at'] if len(items) > limit and sliced else None
        return success_response(data={'results': sliced, 'next_cursor': next_cursor})


class TableListView(StaffReadOnlyAPIView):
    def get(self, request, table):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)

        queryset = get_queryset(config)
        queryset = apply_search(queryset, config, request.query_params.get('search'))
        queryset = apply_date_filters(queryset, config, request.query_params)
        queryset = order_queryset(queryset, config)
        return success_response(data=paginate_queryset(queryset, request))


class RecordDetailView(StaffReadOnlyAPIView):
    def get(self, request, table, record_id):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)
        try:
            instance = get_queryset(config).get(pk=record_id)
        except (config.model.DoesNotExist, ValueError, ValidationError):
            return error_response('not_found', 'Record not found.', status=404)

        record = serialize_instance(instance)
        return success_response(
            data={
                'record': record,
                'related_files': related_files_for_instance(table, instance),
                'raw': record,
            }
        )


class StorageObjectsView(StaffReadOnlyAPIView):
    def get(self, request):
        configured_bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
        bucket = request.query_params.get('bucket') or configured_bucket
        if not configured_bucket or bucket != configured_bucket:
            return error_response('invalid_bucket', 'Bucket is not allowed.', status=400)

        prefix = safe_prefix(request.query_params.get('prefix', ''))
        if prefix is None:
            return error_response('invalid_prefix', 'Prefix is not allowed.', status=400)

        page = parse_positive_int(request.query_params.get('page'), 1, 10**9)
        page_size = parse_positive_int(
            request.query_params.get('page_size'),
            DEFAULT_PAGE_SIZE,
            MAX_PAGE_SIZE,
        )
        orphan_filter = request.query_params.get('orphan')
        if orphan_filter is not None:
            orphan_filter = orphan_filter.lower() in {'true', '1', 'yes'}

        try:
            response = get_s3_client().list_objects_v2(Bucket=bucket, Prefix=prefix)
        except Exception as exc:
            return error_response('storage_error', str(exc), status=502)

        linked = collect_linked_file_map()
        objects = []
        for item in response.get('Contents', []):
            key = item.get('Key', '')
            link = linked.get(key)
            is_orphan = link is None
            if orphan_filter is not None and is_orphan != orphan_filter:
                continue
            objects.append(
                {
                    'bucket': bucket,
                    'object_key': key,
                    'size': item.get('Size'),
                    'last_modified': normalize_value(item.get('LastModified')),
                    'content_type': item.get('ContentType'),
                    'linked_table': link.get('linked_table') if link else None,
                    'linked_record_id': link.get('linked_record_id') if link else None,
                    'orphan': is_orphan,
                }
            )

        count = len(objects)
        start = (page - 1) * page_size
        end = start + page_size
        return success_response(
            data={
                'results': objects[start:end],
                'count': count,
                'page': page,
                'page_size': page_size,
            }
        )


class LogsView(StaffReadOnlyAPIView):
    def get(self, request):
        stream = request.query_params.get('stream') or 'runtime'
        if stream not in LOG_STREAMS:
            return error_response('invalid_stream', 'Log stream is not allowed.', status=400)
        lines = parse_positive_int(
            request.query_params.get('lines'),
            DEFAULT_LOG_LINES,
            MAX_LOG_LINES,
        )
        return success_response(
            data={
                'stream': stream,
                'lines': read_log_stream(stream, lines),
                'next_cursor': None,
            }
        )
