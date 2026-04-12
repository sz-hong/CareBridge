from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ViewSet

from core.responses import success_response

from .models import SOSRecord
from .serializers import SOSRecordSerializer, TriggerSOSSerializer


class SOSViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    @action(detail=False, methods=['post'], url_path='trigger')
    def trigger(self, request):
        serializer = TriggerSOSSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        sos = SOSRecord.objects.create(
            family=request.user.family,
            triggered_by=request.user,
            location=serializer.validated_data.get('location'),
            situation=serializer.validated_data.get('situation', ''),
            status=SOSRecord.Status.TRIGGERED,
        )
        return success_response(
            data=SOSRecordSerializer(sos).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['get'], url_path='history')
    def history(self, request):
        qs = SOSRecord.objects.filter(
            family=request.user.family,
        ).select_related('triggered_by')
        serializer = SOSRecordSerializer(qs, many=True)
        return success_response(data=serializer.data)
