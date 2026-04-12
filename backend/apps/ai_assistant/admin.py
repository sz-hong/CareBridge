from django.contrib import admin

from .models import AIConversation, FirstAidDocument


@admin.register(AIConversation)
class AIConversationAdmin(admin.ModelAdmin):
    list_display = ('user', 'family', 'tokens_used', 'created_at', 'updated_at')
    list_filter = ('created_at', 'updated_at')
    search_fields = ('user__name', 'user__email', 'family__name')
    readonly_fields = ('id', 'created_at', 'updated_at')


@admin.register(FirstAidDocument)
class FirstAidDocumentAdmin(admin.ModelAdmin):
    list_display = ('title', 'source', 'section', 'created_at')
    list_filter = ('source', 'created_at')
    search_fields = ('title', 'source', 'section', 'content')
    readonly_fields = ('id', 'created_at')
