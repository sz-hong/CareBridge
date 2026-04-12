from rest_framework.views import exception_handler
from rest_framework import status
from rest_framework.exceptions import (
    ValidationError,
    AuthenticationFailed,
    NotAuthenticated,
    PermissionDenied,
    NotFound,
    MethodNotAllowed,
    Throttled,
)


def custom_exception_handler(exc, context):
    """
    Custom DRF exception handler that returns a uniform response format:
    {"success": false, "error": {"code": "...", "message": "..."}}
    """
    response = exception_handler(exc, context)

    if response is None:
        return None

    error_code = _get_error_code(exc)
    error_message = _get_error_message(exc, response)

    response.data = {
        'success': False,
        'error': {
            'code': error_code,
            'message': error_message,
        },
    }

    return response


def _get_error_code(exc):
    """Map exception types to error code strings."""
    if isinstance(exc, ValidationError):
        return 'validation_error'
    elif isinstance(exc, (AuthenticationFailed, NotAuthenticated)):
        return 'authentication_error'
    elif isinstance(exc, PermissionDenied):
        return 'permission_denied'
    elif isinstance(exc, NotFound):
        return 'not_found'
    elif isinstance(exc, MethodNotAllowed):
        return 'method_not_allowed'
    elif isinstance(exc, Throttled):
        return 'throttled'
    else:
        return 'error'


def _get_error_message(exc, response):
    """Extract a human-readable error message from the exception."""
    if isinstance(exc, ValidationError):
        # Flatten validation errors into a readable string
        detail = exc.detail
        if isinstance(detail, list):
            return '; '.join(str(item) for item in detail)
        elif isinstance(detail, dict):
            messages = []
            for field, errors in detail.items():
                if isinstance(errors, list):
                    field_msgs = ', '.join(str(e) for e in errors)
                else:
                    field_msgs = str(errors)
                messages.append(f'{field}: {field_msgs}')
            return '; '.join(messages)
        return str(detail)
    elif isinstance(exc, Throttled):
        wait = exc.wait
        if wait is not None:
            return f'Request was throttled. Expected available in {int(wait)} seconds.'
        return 'Request was throttled.'
    elif hasattr(exc, 'detail'):
        return str(exc.detail)
    return str(exc)
