class FamilyScopedQuerySetMixin:
    """Limit queryset results to the authenticated user's current family."""

    family_field = "family"

    def get_request_family(self):
        user = getattr(self.request, "user", None)
        return getattr(user, "family", None)

    def scope_queryset_to_family(self, queryset):
        family = self.get_request_family()
        if family is None:
            return queryset.none()
        return queryset.filter(**{self.family_field: family})
