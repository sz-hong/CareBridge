from rest_framework.permissions import BasePermission


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
