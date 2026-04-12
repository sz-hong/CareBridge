from rest_framework.response import Response


def success_response(data=None, status=200, meta=None):
    body = {"success": True, "data": data}
    if meta:
        body["meta"] = meta
    return Response(body, status=status)
