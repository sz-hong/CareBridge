from django.contrib import admin

from .models import Expense


@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ('store_name', 'total_amount', 'date', 'status', 'recorder', 'family', 'created_at')
    list_filter = ('status', 'date', 'created_at')
    search_fields = ('store_name', 'recorder__name', 'recorder__email', 'family__name')
    readonly_fields = ('id', 'created_at', 'updated_at')
