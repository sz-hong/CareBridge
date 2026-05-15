from django.urls import path

from .views import (
    AIChatView,
    CareAnalysisView,
    HandoverReportView,
    SubsidyFormView,
    FirstAidScenarioListView,
    FirstAidView,
)

urlpatterns = [
    path('chat/', AIChatView.as_view(), name='ai-chat'),
    path('care-analysis/', CareAnalysisView.as_view(), name='ai-care-analysis'),
    path('handover-report/', HandoverReportView.as_view(), name='ai-handover-report'),
    path('subsidy-form/', SubsidyFormView.as_view(), name='ai-subsidy-form'),
    path('first-aid/scenarios/', FirstAidScenarioListView.as_view(), name='ai-first-aid-scenarios'),
    path('first-aid/', FirstAidView.as_view(), name='ai-first-aid'),
]
