from django.contrib import admin

from .models import BoardRequest


@admin.register(BoardRequest)
class BoardRequestAdmin(admin.ModelAdmin):
    list_display = ('requester', 'category', 'status', 'family', 'reviewed_by', 'created_at')
    list_filter = ('category', 'status', 'created_at')
    search_fields = ('requester__name', 'requester__email', 'note', 'family__name')
    readonly_fields = ('id', 'created_at', 'updated_at')
