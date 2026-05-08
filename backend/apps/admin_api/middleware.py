import time

from rest_framework.request import Request
from rest_framework_simplejwt.authentication import JWTAuthentication

from .models import AdminRequestLog


class AdminRequestLogMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        started = time.monotonic()
        try:
            response = self.get_response(request)
        except Exception as exc:
            self.write_log(request, 500, started, exc=exc)
            raise

        self.write_log(request, getattr(response, 'status_code', 0), started, response)
        return response

    def write_log(self, request, status_code, started, response=None, exc=None):
        if not request.path.startswith('/api/v1/'):
            return

        error_code, error_message = self.extract_error(response, exc)
        user = self.resolve_user(request)
        try:
            AdminRequestLog.objects.create(
                request_id=self.request_id(request),
                method=request.method.upper(),
                path=request.path,
                query=request.META.get('QUERY_STRING', ''),
                status_code=status_code or 0,
                duration_ms=max(0, int((time.monotonic() - started) * 1000)),
                user_id=str(getattr(user, 'id', '') or '') or None,
                user_email=getattr(user, 'email', None) or None,
                is_staff=bool(getattr(user, 'is_staff', False)),
                ip=self.client_ip(request),
                user_agent=request.META.get('HTTP_USER_AGENT', ''),
                error_code=error_code,
                error_message=error_message,
                metadata={},
            )
        except Exception:
            # Request monitoring must never break the API it observes.
            return

    def resolve_user(self, request):
        user = getattr(request, 'user', None)
        if getattr(user, 'is_authenticated', False):
            return user

        forced_user = getattr(request, '_force_auth_user', None)
        if getattr(forced_user, 'is_authenticated', False):
            return forced_user

        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if not auth_header.lower().startswith('bearer '):
            return None

        try:
            authenticated = JWTAuthentication().authenticate(Request(request))
        except Exception:
            return None
        if not authenticated:
            return None
        return authenticated[0]

    def extract_error(self, response=None, exc=None):
        if exc is not None:
            return exc.__class__.__name__, str(exc)

        data = getattr(response, 'data', None)
        if not isinstance(data, dict):
            return None, None

        error = data.get('error')
        if not isinstance(error, dict):
            return None, None
        return error.get('code'), error.get('message')

    def request_id(self, request):
        return request.META.get('HTTP_X_REQUEST_ID') or request.META.get(
            'HTTP_X_CORRELATION_ID'
        )

    def client_ip(self, request):
        forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if forwarded_for:
            return forwarded_for.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR')
