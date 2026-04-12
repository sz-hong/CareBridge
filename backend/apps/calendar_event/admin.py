from django.contrib import admin

from .models import Event


@admin.register(Event)
class EventAdmin(admin.ModelAdmin):
    list_display = ('title', 'type', 'source', 'family', 'start_time', 'end_time', 'location', 'created_by')
    list_filter = ('type', 'source', 'start_time')
    search_fields = ('title', 'location', 'note', 'family__name', 'created_by__name')
    readonly_fields = ('id', 'created_at')
