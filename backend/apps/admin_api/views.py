import mimetypes
import posixpath
import re
import uuid
from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.paginator import EmptyPage, Paginator
from django.db import IntegrityError, models
from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
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
from core.permissions import CaregiverCannotDelete
from apps.todo.models import Todo
from core.responses import error_response, success_response
from core.storage import _get_s3_client, build_public_url, extract_key_from_url

from .models import AdminMutationAuditLog, AdminRequestLog


MAX_PAGE_SIZE = 100
DEFAULT_PAGE_SIZE = 20
MAX_ACTIVITY_LIMIT = 100
DEFAULT_ACTIVITY_LIMIT = 12
MAX_LOG_LINES = 500
DEFAULT_LOG_LINES = 100
PRESIGN_EXPIRES_IN = 300
MAX_UPLOAD_SIZE = 10 * 1024 * 1024

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

MUTABLE_TABLES = {
    'care_logs',
    'board_requests',
    'todos',
    'events',
    'health_data',
    'health_alerts',
    'health_thresholds',
    'expenses',
    'documents',
}

FILE_UPLOAD_TABLES = {
    'care_logs',
    'expenses',
    'documents',
}

ALLOWED_UPLOAD_CONTENT_TYPES = {
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'text/plain',
}


@dataclass(frozen=True)
class TableConfig:
    model: object
    search_fields: tuple[str, ...] = ()
    date_fields: tuple[str, ...] = ('updated_at', 'created_at')
    actor_fields: tuple[str, ...] = ()
    mutable: bool = False


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
        mutable=True,
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
        mutable=True,
    ),
    'todos': TableConfig(
        model=Todo,
        search_fields=('title', 'priority', 'status', 'assignee__email', 'assignee__name'),
        actor_fields=('created_by', 'assignee'),
        mutable=True,
    ),
    'events': TableConfig(
        model=Event,
        search_fields=('title', 'type', 'location', 'note'),
        date_fields=('created_at', 'start_time'),
        actor_fields=('created_by',),
        mutable=True,
    ),
    'health_data': TableConfig(
        model=HealthData,
        search_fields=('type', 'unit', 'device_id'),
        date_fields=('created_at', 'recorded_at'),
        mutable=True,
    ),
    'health_alerts': TableConfig(
        model=HealthAlert,
        search_fields=('type', 'severity'),
        date_fields=('created_at', 'recorded_at', 'acknowledged_at'),
        actor_fields=('acknowledged_by',),
        mutable=True,
    ),
    'health_thresholds': TableConfig(
        model=HealthAlertThreshold,
        search_fields=('family__name',),
        date_fields=('updated_at',),
        actor_fields=('updated_by',),
        mutable=True,
    ),
    'expenses': TableConfig(
        model=Expense,
        search_fields=('store_name', 'status', 'recorder__email', 'recorder__name'),
        date_fields=('updated_at', 'created_at', 'date'),
        actor_fields=('recorder',),
        mutable=True,
    ),
    'documents': TableConfig(
        model=Document,
        search_fields=('title', 'category', 'mime_type', 'uploaded_by__email'),
        actor_fields=('uploaded_by',),
        mutable=True,
    ),
}

EXTRA_FILE_MODELS = {
    'medication_confirmations': MedicationConfirmation,
}

LOG_STREAMS = {
    'api-errors': 'api-errors.log',
    'runtime': 'runtime.log',
}

LOOKUP_CONFIGS = {
    'users': {
        'model': User,
        'search_fields': ('email', 'name', 'phone'),
    },
    'families': {
        'model': Family,
        'search_fields': ('name', 'elder_name', 'invite_code'),
    },
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
    permission_classes = [IsAuthenticated, IsActiveStaff, CaregiverCannotDelete]
    http_method_names = ['get', 'options']


class StaffAdminAPIView(APIView):
    permission_classes = [IsAuthenticated, IsActiveStaff, CaregiverCannotDelete]
    http_method_names = ['get', 'post', 'delete', 'options']


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


def validation_error_response(message, fields=None, status=400):
    body = {
        'success': False,
        'error': {
            'code': 'validation_error',
            'message': message,
        },
    }
    if fields is not None:
        body['error']['fields'] = normalize_validation_fields(fields)
    return Response(body, status=status)


def normalize_validation_fields(fields):
    if hasattr(fields, 'message_dict'):
        fields = fields.message_dict
    if isinstance(fields, dict):
        return {
            field: [str(message) for message in messages]
            if isinstance(messages, (list, tuple))
            else [str(messages)]
            for field, messages in fields.items()
        }
    return {'non_field_errors': [str(fields)]}


def request_id_for(request):
    return request.headers.get('X-Request-ID') or request.headers.get('X-Correlation-ID')


def write_audit_log(
    request,
    action,
    status_code=200,
    table=None,
    record_id=None,
    bucket=None,
    object_key=None,
    metadata=None,
):
    user = getattr(request, 'user', None)
    AdminMutationAuditLog.objects.create(
        request_id=request_id_for(request),
        actor=user if getattr(user, 'is_authenticated', False) else None,
        actor_email=getattr(user, 'email', None) or None,
        action=action,
        table=table,
        record_id=str(record_id) if record_id is not None else None,
        bucket=bucket,
        object_key=object_key,
        status_code=status_code,
        metadata=metadata or {},
    )


def deleted_record_ids(table):
    return set(
        AdminMutationAuditLog.objects.filter(
            action=AdminMutationAuditLog.Action.DELETE,
            table=table,
        ).values_list('record_id', flat=True)
    )


def is_admin_deleted(table, record_id):
    return AdminMutationAuditLog.objects.filter(
        action=AdminMutationAuditLog.Action.DELETE,
        table=table,
        record_id=str(record_id),
    ).exists()


def mutation_allowed(config):
    return config.mutable


def is_single_relation_field(field):
    return field.is_relation and (field.many_to_one or field.one_to_one)


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
        if is_single_relation_field(field):
            key = f'{field.name}_id'
            value = getattr(instance, field.attname)
        else:
            key = field.name
            value = getattr(instance, field.name)
        data[key] = normalize_value(value)
    return data


def field_has_default(field):
    return field.has_default() or getattr(field, 'auto_now', False) or getattr(
        field, 'auto_now_add', False
    )


def create_values_for_model(model, payload):
    values = {}
    errors = {}
    allowed_keys = set()

    for field in model._meta.fields:
        if field.primary_key or not field.editable:
            continue

        if is_single_relation_field(field):
            input_key = f'{field.name}_id'
            allowed_keys.add(input_key)
            allowed_keys.add(field.name)
            if input_key in payload:
                values[field.attname] = payload[input_key]
            elif field.name in payload:
                values[field.attname] = payload[field.name]
            elif not field_has_default(field) and not field.blank and not field.null:
                errors[input_key] = ['This field is required.']
            continue

        allowed_keys.add(field.name)
        if field.name in payload:
            values[field.name] = payload[field.name]
        elif not field_has_default(field) and not field.blank and not field.null:
            errors[field.name] = ['This field is required.']

    unknown_keys = set(payload.keys()) - allowed_keys
    for key in sorted(unknown_keys):
        errors[key] = ['Unknown field.']

    return values, errors


def create_record_from_payload(config, payload):
    values, errors = create_values_for_model(config.model, payload)
    if errors:
        raise ValidationError(errors)

    instance = config.model(**values)
    instance.full_clean()
    instance.save()
    return instance


def lookup_resource_for_model(model):
    if model == User:
        return 'users'
    if model == Family:
        return 'families'
    return None


def field_default(field):
    if not field.has_default():
        return None
    default = field.default
    if callable(default):
        return None
    return normalize_value(default)


def field_required(field):
    return not field_has_default(field) and not field.blank and not field.null


def field_choices(field):
    if not getattr(field, 'choices', None):
        return []
    return [
        {
            'value': normalize_value(value),
            'label': str(label),
        }
        for value, label in field.choices
    ]


def field_type_and_control(field):
    if getattr(field, 'choices', None):
        return 'choice', 'select'
    if isinstance(field, models.TextField):
        return 'string', 'textarea'
    if isinstance(field, (models.EmailField,)):
        return 'string', 'email'
    if isinstance(field, (models.URLField,)):
        return 'string', 'url'
    if isinstance(field, (models.CharField,)):
        return 'string', 'text'
    if isinstance(field, (models.IntegerField,)):
        return 'integer', 'number'
    if isinstance(field, (models.DecimalField, models.FloatField)):
        return 'decimal', 'number'
    if isinstance(field, models.BooleanField):
        return 'boolean', 'checkbox'
    if isinstance(field, models.DateTimeField):
        return 'datetime', 'datetime'
    if isinstance(field, models.DateField):
        return 'date', 'date'
    if isinstance(field, models.JSONField):
        return 'json', 'json'
    return 'string', 'text'


def field_schema(field, readonly=False):
    if is_single_relation_field(field):
        resource = lookup_resource_for_model(field.remote_field.model)
        schema = {
            'name': f'{field.name}_id',
            'label': field.verbose_name.replace('_', ' ').title(),
            'type': 'relation' if resource else 'string',
            'control': 'relation' if resource else 'uuid',
            'required': field_required(field),
            'readonly': readonly,
            'default': field_default(field),
            'choices': [],
        }
        if resource:
            schema['relation'] = {
                'resource': resource,
                'lookup_url': f'/api/v1/admin/lookups/{resource}/',
            }
        return schema

    field_type, control = field_type_and_control(field)
    return {
        'name': field.name,
        'label': field.verbose_name.replace('_', ' ').title(),
        'type': field_type,
        'control': control,
        'required': field_required(field),
        'readonly': readonly,
        'default': field_default(field),
        'choices': field_choices(field),
    }


def schema_fields_for_config(config, readonly=False):
    fields = []
    for field in config.model._meta.fields:
        if is_sensitive_field(field.name):
            continue
        if readonly:
            fields.append(field_schema(field, readonly=True))
            continue
        if field.primary_key or not field.editable or field_has_default(field):
            if getattr(field, 'auto_now', False) or getattr(field, 'auto_now_add', False):
                continue
        if field.primary_key or not field.editable:
            continue
        fields.append(field_schema(field, readonly=False))
    return fields


def filename_for_key(key):
    return posixpath.basename(key) if key else None


def guess_content_type(filename):
    content_type, _encoding = mimetypes.guess_type(filename or '')
    return content_type


def is_previewable(content_type, filename=None):
    content_type = content_type or guess_content_type(filename)
    return bool(
        content_type
        and (content_type.startswith('image/') or content_type == 'application/pdf')
    )


def enrich_related_file(file_info, instance=None):
    filename = filename_for_key(file_info.get('object_key'))
    content_type = file_info.get('content_type')
    size = file_info.get('size')
    if instance is not None:
        content_type = content_type or getattr(instance, 'mime_type', None)
        size = size if size is not None else getattr(instance, 'file_size', None)
    return {
        **file_info,
        'filename': filename,
        'content_type': content_type,
        'size': size,
        'previewable': is_previewable(content_type, filename),
    }


def safe_object_key(value):
    if not value:
        return None
    key = str(value).replace('\\', '/').lstrip('/')
    parts = [part for part in key.split('/') if part]
    if not parts or any(part == '..' for part in parts):
        return None
    return '/'.join(parts)


def safe_upload_filename(name):
    filename = posixpath.basename(str(name).replace('\\', '/'))
    filename = re.sub(r'[^A-Za-z0-9._-]+', '_', filename).strip('._')
    return filename or 'upload.bin'


def safe_upload_segment(value, default):
    if not value:
        return default
    text = str(value).strip()
    if '..' in text or '/' in text or '\\' in text:
        return None
    return safe_upload_filename(text)


def configured_bucket_or_error(bucket):
    configured_bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
    requested_bucket = bucket or configured_bucket
    if not configured_bucket or requested_bucket != configured_bucket:
        return None
    return requested_bucket


def get_queryset(config, table=None, include_deleted=False):
    queryset = config.model.objects.all()
    related_fields = [
        field.name
        for field in config.model._meta.fields
        if field.is_relation and field.many_to_one
    ]
    if related_fields:
        queryset = queryset.select_related(*related_fields)
    if table and not include_deleted and mutation_allowed(config):
        deleted_ids = deleted_record_ids(table)
        if deleted_ids:
            queryset = queryset.exclude(pk__in=deleted_ids)
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


def paginate_items(items, request):
    page_size = parse_positive_int(
        request.query_params.get('page_size'),
        DEFAULT_PAGE_SIZE,
        MAX_PAGE_SIZE,
    )
    requested_page = parse_positive_int(request.query_params.get('page'), 1, 10**9)
    paginator = Paginator(items, page_size)
    try:
        page = paginator.page(requested_page)
    except EmptyPage:
        page = paginator.page(paginator.num_pages or 1)
    return {
        'results': list(page.object_list),
        'count': paginator.count,
        'next': page.next_page_number() if page.has_next() else None,
        'previous': page.previous_page_number() if page.has_previous() else None,
        'page': page.number,
        'page_size': page_size,
    }


def lookup_label(resource, instance):
    if resource == 'users':
        name = getattr(instance, 'name', '') or getattr(instance, 'email', '')
        email = getattr(instance, 'email', '')
        return f'{name} ({email})' if email else name
    if resource == 'families':
        return getattr(instance, 'name', '') or str(instance.pk)
    return str(instance)


def serialize_lookup_item(resource, instance):
    raw = serialize_instance(instance)
    return {
        'id': str(instance.pk),
        'label': lookup_label(resource, instance),
        'raw': raw,
    }


def serialize_request_log(log):
    return {
        'id': str(log.id),
        'request_id': log.request_id,
        'method': log.method,
        'path': log.path,
        'query': log.query,
        'status_code': log.status_code,
        'status_class': f'{int(log.status_code / 100)}xx' if log.status_code else None,
        'success': 200 <= log.status_code < 400,
        'duration_ms': log.duration_ms,
        'user_id': log.user_id,
        'user_email': log.user_email,
        'is_staff': log.is_staff,
        'ip': log.ip,
        'user_agent': log.user_agent,
        'error_code': log.error_code,
        'error_message': log.error_message,
        'created_at': normalize_value(log.created_at),
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
            enrich_related_file(
                {
                    'bucket': bucket,
                    'object_key': key,
                    'size': None,
                    'last_modified': None,
                    'content_type': None,
                    'linked_table': table,
                    'linked_record_id': str(instance.pk),
                    'orphan': False,
                },
                instance=instance,
            )
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
        queryset = model.objects.all()
        if table in TABLES and TABLES[table].mutable:
            deleted_ids = deleted_record_ids(table)
            if deleted_ids:
                queryset = queryset.exclude(pk__in=deleted_ids)
        for instance in queryset:
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
            queryset = get_queryset(config, table=table)
            tables.append(
                {
                    'table': table,
                    'count': queryset.count(),
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
                queryset = get_queryset(config, table=table)
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


class TableSchemaView(StaffReadOnlyAPIView):
    def get(self, request, table):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)

        create_allowed = mutation_allowed(config)
        fields = schema_fields_for_config(config, readonly=not create_allowed)
        return success_response(
            data={
                'table': table,
                'create_allowed': create_allowed,
                'delete_allowed': create_allowed,
                'fields': fields,
            }
        )


class LookupView(StaffReadOnlyAPIView):
    def get(self, request, resource):
        config = LOOKUP_CONFIGS.get(resource)
        if not config:
            return error_response('not_found', 'Lookup resource not found.', status=404)

        queryset = config['model'].objects.all()
        search = request.query_params.get('search')
        if search:
            query = Q()
            for field_name in config['search_fields']:
                query |= Q(**{f'{field_name}__icontains': search})
            queryset = queryset.filter(query)
        queryset = queryset.order_by('-created_at') if model_has_field(config['model'], 'created_at') else queryset.order_by('-pk')
        items = [serialize_lookup_item(resource, item) for item in queryset]
        return success_response(data=paginate_items(items, request))


class TableListView(StaffAdminAPIView):
    http_method_names = ['get', 'post', 'options']

    def get(self, request, table):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)

        queryset = get_queryset(config, table=table)
        queryset = apply_search(queryset, config, request.query_params.get('search'))
        queryset = apply_date_filters(queryset, config, request.query_params)
        queryset = order_queryset(queryset, config)
        return success_response(data=paginate_queryset(queryset, request))

    def post(self, request, table):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)
        if not mutation_allowed(config):
            return error_response(
                'mutation_not_allowed',
                'This admin table is read-only.',
                status=403,
            )
        if not isinstance(request.data, dict):
            return validation_error_response('Invalid request body.')

        try:
            instance = create_record_from_payload(config, request.data)
        except ValidationError as exc:
            return validation_error_response('Invalid request body.', exc)
        except IntegrityError as exc:
            return validation_error_response(str(exc), {'non_field_errors': [str(exc)]})

        write_audit_log(
            request,
            AdminMutationAuditLog.Action.CREATE,
            status_code=201,
            table=table,
            record_id=instance.pk,
        )
        record = serialize_instance(instance)
        return success_response(
            data={
                'record': record,
                'raw': record,
            },
            status=201,
        )


class RecordDetailView(StaffAdminAPIView):
    http_method_names = ['get', 'delete', 'options']

    def get(self, request, table, record_id):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)
        try:
            instance = get_queryset(config, table=table).get(pk=record_id)
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

    def delete(self, request, table, record_id):
        config = get_table_config(table)
        if not config:
            return error_response('not_found', 'Admin table not found.', status=404)
        if not mutation_allowed(config):
            return error_response(
                'mutation_not_allowed',
                'This admin table is read-only.',
                status=403,
            )
        try:
            instance = get_queryset(config, table=table).get(pk=record_id)
        except (config.model.DoesNotExist, ValueError, ValidationError):
            return error_response('not_found', 'Record not found.', status=404)

        deleted_at = timezone.now()
        write_audit_log(
            request,
            AdminMutationAuditLog.Action.DELETE,
            table=table,
            record_id=instance.pk,
            metadata={'delete_mode': 'soft'},
        )
        return success_response(
            data={
                'table': table,
                'id': str(instance.pk),
                'deleted': True,
                'delete_mode': 'soft',
                'deleted_at': normalize_value(deleted_at),
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
                enrich_related_file(
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


class FilePresignView(StaffReadOnlyAPIView):
    def get(self, request):
        bucket = configured_bucket_or_error(request.query_params.get('bucket'))
        if not bucket:
            return error_response('invalid_bucket', 'Bucket is not allowed.', status=400)

        object_key = safe_object_key(request.query_params.get('object_key'))
        if not object_key:
            return error_response('invalid_object_key', 'Object key is not allowed.', status=400)

        mode = request.query_params.get('mode')
        if mode not in {'preview', 'download'}:
            return error_response('invalid_mode', 'Mode must be preview or download.', status=400)

        disposition = 'inline' if mode == 'preview' else 'attachment'
        filename = filename_for_key(object_key)
        content_type = guess_content_type(filename)
        client = get_s3_client()

        try:
            metadata = client.head_object(Bucket=bucket, Key=object_key)
            content_type = metadata.get('ContentType') or content_type
            size = metadata.get('ContentLength')
        except Exception:
            return error_response('not_found', 'Storage object not found.', status=404)

        params = {
            'Bucket': bucket,
            'Key': object_key,
            'ResponseContentDisposition': f'{disposition}; filename="{filename}"',
        }
        if content_type:
            params['ResponseContentType'] = content_type

        try:
            url = client.generate_presigned_url(
                ClientMethod='get_object',
                Params=params,
                ExpiresIn=PRESIGN_EXPIRES_IN,
            )
        except Exception as exc:
            return error_response('presign_error', str(exc), status=502)

        action = (
            AdminMutationAuditLog.Action.PRESIGN_PREVIEW
            if mode == 'preview'
            else AdminMutationAuditLog.Action.PRESIGN_DOWNLOAD
        )
        write_audit_log(
            request,
            action,
            bucket=bucket,
            object_key=object_key,
            metadata={'mode': mode},
        )
        return success_response(
            data={
                'url': url,
                'expires_in': PRESIGN_EXPIRES_IN,
                'content_type': content_type,
                'filename': filename,
                'size': size,
                'disposition': disposition,
            }
        )


class FileUploadView(StaffAdminAPIView):
    http_method_names = ['post', 'options']

    def post(self, request):
        bucket = configured_bucket_or_error(request.data.get('bucket'))
        if not bucket:
            return error_response('invalid_bucket', 'Bucket is not allowed.', status=400)

        table = request.data.get('table')
        if table not in FILE_UPLOAD_TABLES:
            return error_response(
                'invalid_table',
                'File upload is not allowed for this table.',
                status=400,
            )

        uploaded_file = request.FILES.get('file')
        if not uploaded_file:
            return validation_error_response(
                'Invalid request body.',
                {'file': ['This field is required.']},
            )

        if uploaded_file.size > MAX_UPLOAD_SIZE:
            return validation_error_response(
                'Invalid request body.',
                {'file': [f'File must be at most {MAX_UPLOAD_SIZE} bytes.']},
            )

        content_type = uploaded_file.content_type or guess_content_type(uploaded_file.name)
        if content_type not in ALLOWED_UPLOAD_CONTENT_TYPES:
            return validation_error_response(
                'Invalid request body.',
                {'file': ['This content type is not allowed.']},
            )

        family_id = safe_upload_segment(request.data.get('family_id'), 'unscoped')
        if family_id is None:
            return validation_error_response(
                'Invalid request body.',
                {'family_id': ['This path segment is not allowed.']},
            )

        purpose = safe_upload_segment(request.data.get('purpose'), 'upload')
        if purpose is None:
            return validation_error_response(
                'Invalid request body.',
                {'purpose': ['This path segment is not allowed.']},
            )

        filename = safe_upload_filename(uploaded_file.name)
        object_key = f'admin/{table}/{family_id}/{purpose}/{uuid.uuid4()}/{filename}'

        try:
            get_s3_client().put_object(
                Bucket=bucket,
                Key=object_key,
                Body=uploaded_file,
                ContentType=content_type,
            )
        except Exception as exc:
            return error_response('upload_error', str(exc), status=502)

        write_audit_log(
            request,
            AdminMutationAuditLog.Action.UPLOAD,
            status_code=201,
            table=table,
            bucket=bucket,
            object_key=object_key,
            metadata={
                'filename': filename,
                'content_type': content_type,
                'size': uploaded_file.size,
            },
        )
        return success_response(
            data={
                'bucket': bucket,
                'object_key': object_key,
                'filename': filename,
                'content_type': content_type,
                'size': uploaded_file.size,
                'url': build_public_url(object_key),
            },
            status=201,
        )


class RequestLogsView(StaffReadOnlyAPIView):
    def get(self, request):
        queryset = AdminRequestLog.objects.all()

        method = request.query_params.get('method')
        if method:
            queryset = queryset.filter(method=method.upper())

        status_code = request.query_params.get('status_code')
        if status_code:
            try:
                queryset = queryset.filter(status_code=int(status_code))
            except ValueError:
                return error_response(
                    'invalid_status_code',
                    'status_code must be an integer.',
                    status=400,
                )

        status_class = request.query_params.get('status_class')
        if status_class:
            match = re.match(r'^([1-5])xx$', status_class.lower())
            if not match:
                return error_response(
                    'invalid_status_class',
                    'status_class must be like 2xx, 4xx, or 5xx.',
                    status=400,
                )
            start = int(match.group(1)) * 100
            queryset = queryset.filter(status_code__gte=start, status_code__lt=start + 100)

        path = request.query_params.get('path')
        if path:
            queryset = queryset.filter(path__icontains=path)

        search = request.query_params.get('search')
        if search:
            queryset = queryset.filter(
                Q(path__icontains=search)
                | Q(query__icontains=search)
                | Q(user_email__icontains=search)
                | Q(request_id__icontains=search)
                | Q(error_code__icontains=search)
                | Q(error_message__icontains=search)
            )

        date_from = parse_lower_bound(request.query_params.get('date_from'))
        if date_from is not None:
            queryset = queryset.filter(created_at__gte=date_from)

        date_to = parse_lower_bound(request.query_params.get('date_to'))
        if date_to is not None:
            queryset = queryset.filter(created_at__lte=date_to)

        queryset = queryset.order_by('-created_at')
        return success_response(
            data=paginate_items(
                [serialize_request_log(log) for log in queryset],
                request,
            )
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
