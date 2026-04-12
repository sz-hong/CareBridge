from django.contrib import admin

from .models import HealthAlert, HealthAlertThreshold, HealthData


@admin.register(HealthData)
class HealthDataAdmin(admin.ModelAdmin):
    list_display = ('type', 'value', 'unit', 'family', 'device_id', 'recorded_at')
    list_filter = ('type', 'unit', 'recorded_at')
    search_fields = ('device_id', 'family__name')
    readonly_fields = ('id', 'created_at')


@admin.register(HealthAlertThreshold)
class HealthAlertThresholdAdmin(admin.ModelAdmin):
    list_display = ('family', 'heart_rate_high', 'heart_rate_low', 'blood_oxygen_low', 'updated_by', 'updated_at')
    search_fields = ('family__name',)
    readonly_fields = ('id', 'updated_at')


@admin.register(HealthAlert)
class HealthAlertAdmin(admin.ModelAdmin):
    list_display = ('type', 'severity', 'value', 'threshold', 'family', 'acknowledged_by', 'recorded_at', 'created_at')
    list_filter = ('severity', 'type', 'created_at')
    search_fields = ('family__name', 'type')
    readonly_fields = ('id', 'created_at')
