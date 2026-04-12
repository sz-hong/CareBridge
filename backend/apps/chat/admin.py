from django.contrib import admin

from .models import Chat, ChatMember, Message


class ChatMemberInline(admin.TabularInline):
    model = ChatMember
    extra = 0
    readonly_fields = ('joined_at',)


@admin.register(Chat)
class ChatAdmin(admin.ModelAdmin):
    list_display = ('name', 'type', 'family', 'created_at')
    list_filter = ('type', 'created_at')
    search_fields = ('name', 'family__name')
    readonly_fields = ('id', 'created_at')
    inlines = [ChatMemberInline]


@admin.register(ChatMember)
class ChatMemberAdmin(admin.ModelAdmin):
    list_display = ('chat', 'user', 'joined_at')
    list_filter = ('joined_at',)
    search_fields = ('user__name', 'user__email', 'chat__name')


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ('sender', 'chat', 'type', 'content_preview', 'sent_at')
    list_filter = ('type', 'sent_at')
    search_fields = ('content', 'sender__name', 'sender__email')
    readonly_fields = ('id', 'sent_at')

    @admin.display(description='Content')
    def content_preview(self, obj):
        if obj.content:
            return obj.content[:80] + '...' if len(obj.content) > 80 else obj.content
        return '-'
