from django.contrib import admin

from .models import Family


@admin.register(Family)
class FamilyAdmin(admin.ModelAdmin):
    list_display = ('name', 'elder_name', 'elder_birth_date', 'invite_code', 'created_by', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('name', 'elder_name', 'invite_code')
    readonly_fields = ('id', 'created_at')
