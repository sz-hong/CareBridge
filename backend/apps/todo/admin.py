from django.contrib import admin

from .models import Todo


@admin.register(Todo)
class TodoAdmin(admin.ModelAdmin):
    list_display = ('title', 'assignee', 'priority', 'status', 'due_date', 'family', 'created_by', 'created_at')
    list_filter = ('priority', 'status', 'due_date', 'created_at')
    search_fields = ('title', 'assignee__name', 'assignee__email', 'family__name')
    readonly_fields = ('id', 'created_at')
