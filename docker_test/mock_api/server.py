#!/usr/bin/env python3
import json
import os
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


FAMILY_ID = '00000000-0000-4000-8000-000000000100'
USER_ID = '00000000-0000-4000-8000-000000000001'

USER = {
    'id': USER_ID,
    'email': 'frontend@carebridge.test',
    'name': 'Frontend Mock Admin',
    'phone': None,
    'birthday': None,
    'language': 'zh-Hant',
    'role': 'caregiver',
    'avatar_url': None,
    'family_id': FAMILY_ID,
    'family_name': 'Mock Family',
    'family_invite_code': '123456',
    'family': {'id': FAMILY_ID, 'name': 'Mock Family', 'invite_code': '123456'},
    'is_primary': True,
    'is_staff': True,
}

CAPABILITIES = {
    'list': True,
    'detail': True,
    'schema': True,
    'create': True,
    'update': True,
    'delete': True,
}

TABLES = [
    {
        'table': 'todos',
        'display_name': 'Todos',
        'category': 'care',
        'model': 'apps.todo.models.Todo',
        'capabilities': CAPABILITIES,
        'endpoints': {
            'list': '/api/v1/admin/tables/todos/',
            'schema': '/api/v1/admin/tables/todos/schema/',
            'detail': '/api/v1/admin/records/todos/{id}/',
        },
    },
    {
        'table': 'medications',
        'display_name': 'Medications',
        'category': 'care',
        'model': 'apps.medication.models.Medication',
        'capabilities': CAPABILITIES,
        'endpoints': {
            'list': '/api/v1/admin/tables/medications/',
            'schema': '/api/v1/admin/tables/medications/schema/',
            'detail': '/api/v1/admin/records/medications/{id}/',
        },
    },
]

SCHEMAS = {
    'todos': {
        'table': 'todos',
        'create_allowed': True,
        'delete_allowed': True,
        'fields': [
            {'name': 'id', 'label': 'ID', 'type': 'string', 'control': 'uuid', 'required': False, 'readonly': True, 'default': None, 'choices': []},
            {'name': 'title', 'label': 'Title', 'type': 'string', 'control': 'text', 'required': True, 'readonly': False, 'default': '', 'choices': []},
            {'name': 'status', 'label': 'Status', 'type': 'choice', 'control': 'select', 'required': True, 'readonly': False, 'default': 'pending', 'choices': [
                {'value': 'pending', 'label': 'Pending'},
                {'value': 'done', 'label': 'Done'},
            ]},
            {'name': 'created_at', 'label': 'Created at', 'type': 'datetime', 'control': 'datetime', 'required': False, 'readonly': True, 'default': None, 'choices': []},
        ],
    },
    'medications': {
        'table': 'medications',
        'create_allowed': True,
        'delete_allowed': True,
        'fields': [
            {'name': 'id', 'label': 'ID', 'type': 'string', 'control': 'uuid', 'required': False, 'readonly': True, 'default': None, 'choices': []},
            {'name': 'name', 'label': 'Name', 'type': 'string', 'control': 'text', 'required': True, 'readonly': False, 'default': '', 'choices': []},
            {'name': 'dosage', 'label': 'Dosage', 'type': 'string', 'control': 'text', 'required': False, 'readonly': False, 'default': '', 'choices': []},
            {'name': 'active', 'label': 'Active', 'type': 'boolean', 'control': 'checkbox', 'required': False, 'readonly': False, 'default': True, 'choices': []},
            {'name': 'created_at', 'label': 'Created at', 'type': 'datetime', 'control': 'datetime', 'required': False, 'readonly': True, 'default': None, 'choices': []},
        ],
    },
}

RECORDS = {
    'todos': [
        {'id': 'todo-1', 'title': 'Mock care check-in', 'status': 'pending', 'created_at': now_iso()},
        {'id': 'todo-2', 'title': 'Mock medication reminder', 'status': 'done', 'created_at': now_iso()},
    ],
    'medications': [
        {'id': 'med-1', 'name': 'Vitamin D', 'dosage': '1 tablet', 'active': True, 'created_at': now_iso()},
    ],
}

REQUEST_LOGS = [
    {
        'id': 'req-1',
        'request_id': 'mock-request-1',
        'method': 'GET',
        'path': '/api/v1/health/',
        'query': '',
        'status_code': 200,
        'status_class': '2xx',
        'success': True,
        'duration_ms': 2,
        'user_id': USER_ID,
        'user_email': USER['email'],
        'is_staff': True,
        'ip': '127.0.0.1',
        'user_agent': 'docker_test',
        'error_code': None,
        'error_message': None,
        'created_at': now_iso(),
    }
]


ACTIVITY = [
    {
        'id': 'activity-1',
        'table': 'todos',
        'record_id': 'todo-1',
        'action': 'mock_boot',
        'actor': USER['email'],
        'created_at': now_iso(),
    }
]
AUDIT_LOGS = [
    {
        'id': 'audit-1',
        'request_id': 'mock-request-1',
        'actor_id': USER_ID,
        'actor_email': USER['email'],
        'action': 'mock_boot',
        'table': None,
        'record_id': None,
        'bucket': None,
        'object_key': None,
        'status_code': 200,
        'metadata': {'source': 'docker_test'},
        'created_at': now_iso(),
    }
]


def envelope(data):
    return {'success': True, 'data': data}


def page(results, query=None):
    query = query or {}
    page_number = int((query.get('page') or ['1'])[0])
    page_size = int((query.get('page_size') or ['20'])[0])
    search = (query.get('search') or [''])[0].lower()
    filtered = results
    if search:
        filtered = [item for item in results if search in json.dumps(item).lower()]
    start = (page_number - 1) * page_size
    chunk = filtered[start:start + page_size]
    return {
        'results': chunk,
        'count': len(filtered),
        'next': page_number + 1 if start + page_size < len(filtered) else None,
        'previous': page_number - 1 if page_number > 1 else None,
        'page': page_number,
        'page_size': page_size,
    }


def tokens():
    return {
        'access': os.environ.get('MOCK_API_ACCESS_TOKEN', 'mock-access-token'),
        'refresh': os.environ.get('MOCK_API_REFRESH_TOKEN', 'mock-refresh-token'),
    }


def find_record(table, record_id):
    return next((record for record in RECORDS.get(table, []) if str(record.get('id')) == record_id), None)


class Handler(BaseHTTPRequestHandler):
    server_version = 'CareBridgeMockAPI/1.0'

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', os.environ.get('MOCK_API_CORS_ORIGIN', '*'))
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Accept')
        self.send_header('Access-Control-Max-Age', '86400')
        super().end_headers()

    def log_message(self, fmt, *args):
        print('%s - %s' % (self.address_string(), fmt % args), flush=True)

    def read_json(self):
        length = int(self.headers.get('Content-Length', '0'))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode('utf-8'))
        except json.JSONDecodeError:
            return {}

    def write_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def write_error(self, status, code, message):
        self.write_json({'success': False, 'error': {'code': code, 'message': message}}, status)

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path in ('/', '/api/v1/'):
            self.write_json({'service': 'carebridge-docker-test', 'health': '/api/v1/health/'})
        elif path == '/api/v1/health/':
            self.write_json({'status': 'ok', 'service': 'carebridge-docker-test'})
        elif path == '/api/v1/auth/me/':
            self.write_json(envelope(USER))
        elif path == '/api/v1/admin/overview/':
            self.write_json(envelope({
                'kpis': [
                    {'label': 'Users', 'value': 1, 'delta_24h': 0},
                    {'label': 'Families', 'value': 1, 'delta_24h': 0},
                    {'label': 'Open todos', 'value': 1, 'delta_24h': 0},
                ],
                'tables': [{'table': table, 'count': len(RECORDS.get(table, [])), 'created_24h': 0, 'updated_24h': 0} for table in RECORDS],
                'alerts': [{'severity': 'info', 'title': 'Mock API is running', 'count': 1}],
            }))
        elif path == '/api/v1/admin/activity/':
            limit = int((query.get('limit') or ['20'])[0])
            self.write_json(envelope({'results': ACTIVITY[:limit], 'next_cursor': None}))
        elif path == '/api/v1/admin/tables/':
            self.write_json(envelope({'results': TABLES, 'count': len(TABLES)}))
        elif path.startswith('/api/v1/admin/tables/'):
            self.handle_admin_table_get(path, query)
        elif path.startswith('/api/v1/admin/records/'):
            self.handle_record_detail(path)
        elif path == '/api/v1/admin/request-logs/':
            self.write_json(envelope(page(REQUEST_LOGS, query)))
        elif path == '/api/v1/admin/audit-logs/':
            self.write_json(envelope(page(AUDIT_LOGS, query)))
        elif path == '/api/v1/admin/logs/':
            self.write_json(envelope({'stream': (query.get('stream') or ['runtime'])[0], 'lines': [
                {'timestamp': now_iso(), 'level': 'INFO', 'message': 'docker_test mock API is running', 'request_id': None}
            ], 'next_cursor': None}))
        elif path == '/api/v1/admin/storage/objects/':
            self.write_json(envelope(page([], query)))
        elif path == '/api/v1/admin/files/presign/':
            self.write_json(envelope({'url': 'http://127.0.0.1:8001/mock-file', 'expires_in': 300, 'content_type': None, 'filename': None, 'size': None, 'disposition': 'inline'}))
        elif path.startswith('/api/v1/'):
            self.write_json(envelope([]))
        else:
            self.write_error(404, 'not_found', 'No mock endpoint is configured for this path.')

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        body = self.read_json()

        if path == '/api/v1/auth/login/':
            user = dict(USER)
            user['email'] = body.get('email') or USER['email']
            self.write_json(envelope({'user': user, 'tokens': tokens()}))
        elif path in ('/api/v1/auth/token/', '/api/v1/auth/token/refresh/'):
            self.write_json(tokens())
        elif path.startswith('/api/v1/admin/tables/'):
            parts = path.strip('/').split('/')
            table = parts[4] if len(parts) >= 5 else ''
            if table not in RECORDS:
                self.write_error(404, 'unknown_table', 'Unknown mock table.')
                return
            record = dict(body)
            record.setdefault('id', str(uuid.uuid4()))
            record.setdefault('created_at', now_iso())
            RECORDS[table].insert(0, record)
            self.write_json(envelope({'record': record, 'related_files': [], 'raw': record}), 201)
        elif path.startswith('/api/v1/'):
            self.write_json(envelope({'id': str(uuid.uuid4()), 'status': 'mocked', 'received': body}))
        else:
            self.write_error(404, 'not_found', 'No mock endpoint is configured for this path.')

    def do_PATCH(self):
        parsed = urlparse(self.path)
        path = parsed.path
        body = self.read_json()
        if not path.startswith('/api/v1/admin/records/'):
            self.write_json(envelope({'status': 'mocked', 'received': body}))
            return
        table, record_id = self.parse_record_path(path)
        record = find_record(table, record_id)
        if record is None:
            self.write_error(404, 'record_not_found', 'Mock record not found.')
            return
        record.update(body)
        self.write_json(envelope({'record': record, 'related_files': [], 'raw': record}))

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if not path.startswith('/api/v1/admin/records/'):
            self.write_json(envelope({'detail': 'Mock delete accepted.'}))
            return
        table, record_id = self.parse_record_path(path)
        records = RECORDS.get(table, [])
        RECORDS[table] = [record for record in records if str(record.get('id')) != record_id]
        self.write_json(envelope({'deleted': True, 'delete_mode': 'mock'}))

    def handle_admin_table_get(self, path, query):
        parts = path.strip('/').split('/')
        table = parts[4] if len(parts) >= 5 else ''
        if len(parts) >= 6 and parts[5] == 'schema':
            schema = SCHEMAS.get(table)
            if schema is None:
                self.write_error(404, 'unknown_table', 'Unknown mock table.')
                return
            self.write_json(envelope(schema))
            return
        if table not in RECORDS:
            self.write_error(404, 'unknown_table', 'Unknown mock table.')
            return
        self.write_json(envelope(page(RECORDS[table], query)))

    def handle_record_detail(self, path):
        table, record_id = self.parse_record_path(path)
        record = find_record(table, record_id)
        if record is None:
            self.write_error(404, 'record_not_found', 'Mock record not found.')
            return
        self.write_json(envelope({'record': record, 'related_files': [], 'raw': record}))

    def parse_record_path(self, path):
        parts = path.strip('/').split('/')
        table = parts[4] if len(parts) >= 5 else ''
        record_id = parts[5] if len(parts) >= 6 else ''
        return table, record_id


def main():
    host = os.environ.get('MOCK_API_HOST', '0.0.0.0')
    port = int(os.environ.get('MOCK_API_PORT', '8001'))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f'CareBridge docker_test mock API listening on {host}:{port}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()