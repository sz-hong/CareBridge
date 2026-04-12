from django.contrib import admin

from .models import CareLog


@admin.register(CareLog)
class CareLogAdmin(admin.ModelAdmin):
    list_display = ('type', 'recorder', 'family', 'timestamp', 'created_at')
    list_filter = ('type', 'timestamp', 'created_at')
    search_fields = ('recorder__name', 'recorder__email', 'family__name')
    readonly_fields = ('id', 'created_at')
