from rest_framework.permissions import BasePermission, SAFE_METHODS


def _is_caregiver(user):
    return bool(
        user
        and user.is_authenticated
        and getattr(user, 'role', None) == 'caregiver'
    )


class IsFamilyMember(BasePermission):
    """
    Checks that the authenticated user belongs to the family referenced
    in the request (via URL kwarg 'family_id' or request data 'family').
    """
    message = 'You are not a member of this family.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        family_id = (
            view.kwargs.get('family_id')
            or view.kwargs.get('pk')
            or request.data.get('family')
            or request.query_params.get('family')
        )

        if family_id is None:
            return True  # No family context to check

        return request.user.family_memberships.filter(
            family_id=family_id
        ).exists()


class IsCaregiver(BasePermission):
    """
    Checks that the authenticated user has the 'caregiver' role.
    """
    message = 'Only caregivers can perform this action.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return getattr(request.user, 'role', None) == 'caregiver'


class IsFamilyAdmin(BasePermission):
    """
    Checks that the authenticated user is a primary (admin) member
    of the family, i.e. user.is_primary == True.
    """
    message = 'Only family admins can perform this action.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return getattr(request.user, 'is_primary', False) is True


class CaregiverCannotDelete(BasePermission):
    """Prevent caregivers from deleting any API-managed resource."""

    message = 'Caregivers cannot delete records.'

    def has_permission(self, request, view):
        if request.method == 'DELETE' and _is_caregiver(request.user):
            return False
        return True


class CaregiverMedicationPermission(BasePermission):
    """
    Caregivers can read medication schedules and confirm doses, but cannot
    create, update, or delete medication settings.
    """

    message = (
        'Caregivers can read medications and confirm doses, '
        'but cannot manage medication settings.'
    )

    def has_permission(self, request, view):
        if not _is_caregiver(request.user):
            return True
        if request.method in SAFE_METHODS:
            return True
        return request.method == 'POST' and getattr(view, 'action', None) == 'confirm'


class DenyCaregiverDocumentAccess(BasePermission):
    """Block caregivers from the document management API entirely."""

    message = 'Caregivers cannot access document management.'

    def has_permission(self, request, view):
        return not _is_caregiver(request.user)
