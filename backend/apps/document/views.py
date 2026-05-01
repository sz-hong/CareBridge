from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import empty_success_response, success_response
from core.viewsets import FamilyScopedQuerySetMixin

from .models import Document
from .serializers import CreateDocumentSerializer, DocumentSerializer


class DocumentViewSet(FamilyScopedQuerySetMixin, ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = DocumentSerializer

    def get_queryset(self):
        qs = self.scope_queryset_to_family(Document.objects.all())
        category = self.request.query_params.get('category')
        if category:
            qs = qs.filter(category=category)
        return qs.select_related('uploaded_by')

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateDocumentSerializer
        return DocumentSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = DocumentSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = DocumentSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateDocumentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        doc = serializer.save(
            family=request.user.family,
            uploaded_by=request.user,
        )
        return success_response(
            data=DocumentSerializer(doc).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=DocumentSerializer(instance).data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return empty_success_response()
