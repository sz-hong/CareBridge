from django.contrib import admin

from .models import Leave


@admin.register(Leave)
class LeaveAdmin(admin.ModelAdmin):
    list_display = ('applicant', 'type', 'status', 'start_date', 'end_date', 'days', 'reviewed_by', 'created_at')
    list_filter = ('type', 'status', 'created_at')
    search_fields = ('applicant__name', 'applicant__email', 'reason', 'family__name')
    readonly_fields = ('id', 'created_at')
