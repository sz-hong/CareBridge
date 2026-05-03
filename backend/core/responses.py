from rest_framework.response import Response


def success_response(data=None, status=200, meta=None):
    body = {"success": True, "data": data}
    if meta:
        body["meta"] = meta
    return Response(body, status=status)


def empty_success_response(status=200):
    """Return a success envelope for commands that have no resource payload."""
    return success_response(data={}, status=status)


def error_response(code, message, status=400):
    return Response(
        {
            "success": False,
            "error": {
                "code": code,
                "message": message,
            },
        },
        status=status,
    )
