from django.contrib import admin

from .models import SOSRecord


@admin.register(SOSRecord)
class SOSRecordAdmin(admin.ModelAdmin):
    list_display = ('triggered_by', 'status', 'family', 'auto_call_119', 'triggered_at', 'resolved_at')
    list_filter = ('status', 'auto_call_119', 'triggered_at')
    search_fields = ('triggered_by__name', 'triggered_by__email', 'situation', 'family__name')
    readonly_fields = ('id', 'triggered_at')
