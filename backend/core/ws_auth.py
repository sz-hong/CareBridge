from urllib.parse import parse_qs, parse_qsl, urlencode

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.tokens import UntypedToken


def redact_query_token(query_string):
    if not query_string:
        return query_string

    pairs = parse_qsl(query_string.decode(), keep_blank_values=True)
    if not any(key == 'token' for key, _value in pairs):
        return query_string

    redacted_pairs = [
        (key, 'redacted' if key == 'token' else value)
        for key, value in pairs
    ]
    return urlencode(redacted_pairs).encode()


@database_sync_to_async
def get_user(user_id):
    User = get_user_model()
    try:
        return User.objects.get(id=user_id)
    except User.DoesNotExist:
        return AnonymousUser()


class JWTAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        raw_query_string = scope.get('query_string', b'')
        query = parse_qs(raw_query_string.decode())
        token = (query.get('token') or [None])[0]
        scope['query_string'] = redact_query_token(raw_query_string)
        scope['user'] = AnonymousUser()
        if token:
            try:
                validated = UntypedToken(token)
                scope['user'] = await get_user(validated['user_id'])
            except (InvalidToken, TokenError):
                pass
        return await super().__call__(scope, receive, send)
