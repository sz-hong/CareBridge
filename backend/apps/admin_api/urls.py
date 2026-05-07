from django.urls import path

from . import views


urlpatterns = [
    path('overview/', views.OverviewView.as_view(), name='admin-overview'),
    path('activity/', views.ActivityView.as_view(), name='admin-activity'),
    path('tables/<str:table>/', views.TableListView.as_view(), name='admin-table-list'),
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
    path('logs/', views.LogsView.as_view(), name='admin-logs'),
]
