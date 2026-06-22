from django.urls import path

from . import views


urlpatterns = [
    path('overview/', views.OverviewView.as_view(), name='admin-overview'),
    path('activity/', views.ActivityView.as_view(), name='admin-activity'),
    path('tables/', views.TableIndexView.as_view(), name='admin-table-index'),
    path(
        'tables/<str:table>/schema/',
        views.TableSchemaView.as_view(),
        name='admin-table-schema',
    ),
    path('tables/<str:table>/', views.TableListView.as_view(), name='admin-table-list'),
    path(
        'lookups/<str:resource>/',
        views.LookupView.as_view(),
        name='admin-lookup',
    ),
    path(
        'records/<str:table>/<str:record_id>/',
        views.RecordDetailView.as_view(),
        name='admin-record-detail',
    ),
    path(
        'storage/objects/',
        views.StorageObjectsView.as_view(),
        name='admin-storage-objects',
    ),
    path(
        'files/presign/',
        views.FilePresignView.as_view(),
        name='admin-file-presign',
    ),
    path(
        'files/upload/',
        views.FileUploadView.as_view(),
        name='admin-file-upload',
    ),
    path('request-logs/', views.RequestLogsView.as_view(), name='admin-request-logs'),
    path('audit-logs/', views.AuditLogsView.as_view(), name='admin-audit-logs'),
    path('logs/', views.LogsView.as_view(), name='admin-logs'),
]
