"""Cross-app chat helpers shared by auth/family flows."""
from .models import Chat, ChatMember


def enroll_user_in_family_chats(user):
    """Make `user` a member of every existing chat in their current family.

    Called whenever a user joins a family (via invite code, or any other
    path) — without this the chat list filter `members__user=request.user`
    returns nothing for fresh joiners, even though they belong to the
    family that owns those chats.

    Idempotent (uses get_or_create) so re-runs are safe.
    """
    family = getattr(user, 'family', None)
    if family is None:
        return 0

    created = 0
    for chat in Chat.objects.filter(family=family):
        _, was_created = ChatMember.objects.get_or_create(
            chat=chat, user=user,
        )
        if was_created:
            created += 1
    return created
