from django.contrib import admin

from .models import Medication, MedicationConfirmation


@admin.register(Medication)
class MedicationAdmin(admin.ModelAdmin):
    list_display = ('name', 'dosage', 'frequency', 'family', 'is_active', 'reminder_enabled', 'start_date', 'end_date')
    list_filter = ('frequency', 'is_active', 'reminder_enabled', 'created_at')
    search_fields = ('name', 'dosage', 'instructions', 'family__name')
    readonly_fields = ('id', 'created_at', 'updated_at')


@admin.register(MedicationConfirmation)
class MedicationConfirmationAdmin(admin.ModelAdmin):
    list_display = ('medication', 'confirmed_by', 'scheduled_time', 'confirmed_at')
    list_filter = ('confirmed_at',)
    search_fields = ('medication__name', 'confirmed_by__name', 'confirmed_by__email')
    readonly_fields = ('id', 'confirmed_at')
