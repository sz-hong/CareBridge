from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from core.responses import error_response, success_response

from .serializers import ClaimHealthBindingSerializer, HealthBindingSerializer


def serialize_binding(family, current_user) -> dict:
    """Build the binding snapshot a client expects.

    `is_owner` is from the caller's point of view — true iff the binding
    points at the caller. The client uses that to decide whether to keep
    syncing locally or to show a "this family is bound by someone else"
    notice.
    """
    bound_user = family.health_binding_user
    payload = {
        'is_bound': bound_user is not None,
        'is_owner': bound_user is not None and bound_user.id == current_user.id,
        'user_id': str(bound_user.id) if bound_user else None,
        'user_name': bound_user.name if bound_user else None,
        'device_id': family.health_binding_device_id or None,
        'device_label': family.health_binding_device_label or None,
        'claimed_at': family.health_binding_claimed_at,
    }
    return HealthBindingSerializer(payload).data


class FamilyHealthBindingView(APIView):
    """GET / POST / DELETE /families/me/health-binding/

    A single endpoint covers the three operations. Using `me` instead of
    a `<family_id>` PK because every user only has one family and we don't
    want clients having to look it up first. All responses return the
    canonical binding shape so the client can refresh state uniformly.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        family = request.user.family
        if family is None:
            return error_response(
                code='no_family',
                message='User is not in a family.',
                status=400,
            )
        return success_response(data=serialize_binding(family, request.user))

    def post(self, request):
        family = request.user.family
        if family is None:
            return error_response(
                code='no_family',
                message='User is not in a family.',
                status=400,
            )

        serializer = ClaimHealthBindingSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        device_id = serializer.validated_data['device_id']
        device_label = serializer.validated_data.get('device_label', '')

        bound_user = family.health_binding_user
        if bound_user is not None and bound_user.id != request.user.id:
            # 已被別人佔走 — 不靜默覆寫，回 409 讓 UI 顯示「目前由 X 同步」。
            return error_response(
                code='binding_conflict',
                message='Another device in this family is already syncing health data.',
                status=409,
            )

        family.health_binding_user = request.user
        family.health_binding_device_id = device_id
        family.health_binding_device_label = device_label
        family.health_binding_claimed_at = timezone.now()
        family.save(update_fields=[
            'health_binding_user',
            'health_binding_device_id',
            'health_binding_device_label',
            'health_binding_claimed_at',
            'updated_at',
        ])
        return success_response(data=serialize_binding(family, request.user))

    def delete(self, request):
        family = request.user.family
        if family is None:
            return error_response(
                code='no_family',
                message='User is not in a family.',
                status=400,
            )

        bound_user = family.health_binding_user
        if bound_user is None:
            return success_response(data=serialize_binding(family, request.user))
        if bound_user.id != request.user.id:
            # 只有 owner 能釋放自己的綁定；其他人想搶要走 admin 流程或等
            # owner 在 app 內關掉，這樣才能保留「誰在同步」的稽核痕跡。
            return error_response(
                code='not_owner',
                message='Only the current binding owner can release the binding.',
                status=403,
            )

        family.health_binding_user = None
        family.health_binding_device_id = ''
        family.health_binding_device_label = ''
        family.health_binding_claimed_at = None
        family.save(update_fields=[
            'health_binding_user',
            'health_binding_device_id',
            'health_binding_device_label',
            'health_binding_claimed_at',
            'updated_at',
        ])
        return success_response(data=serialize_binding(family, request.user))
