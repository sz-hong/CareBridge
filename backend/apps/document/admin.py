from django.contrib import admin

from .models import Document


@admin.register(Document)
class DocumentAdmin(admin.ModelAdmin):
    list_display = ('title', 'category', 'mime_type', 'file_size', 'uploaded_by', 'family', 'created_at')
    list_filter = ('category', 'mime_type', 'created_at')
    search_fields = ('title', 'uploaded_by__name', 'uploaded_by__email', 'family__name')
    readonly_fields = ('id', 'created_at')
