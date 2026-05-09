from rest_framework import status
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import empty_success_response, success_response
from core.upload_paths import (
    build_quarantine_key,
    is_valid_quarantine_key,
    processed_key_for_raw_key,
)
from core.viewsets import FamilyScopedQuerySetMixin

from .models import Document
from .serializers import CreateDocumentSerializer, DocumentSerializer
from .tasks import deidentify_document_task


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
        raw_file_key = serializer.validated_data.get('raw_file_key')
        if raw_file_key:
            self._validate_document_key(raw_file_key, request.user.family.id)

        doc = serializer.save(
            family=request.user.family,
            uploaded_by=request.user,
        )
        if raw_file_key:
            doc.file_url = None
            doc.raw_file_key = raw_file_key
            doc.redacted_file_key = processed_key_for_raw_key(raw_file_key)
            doc.deid_status = Document.DeidentificationStatus.PROCESSING
            doc.save(update_fields=[
                'file_url',
                'raw_file_key',
                'redacted_file_key',
                'deid_status',
            ])
            deidentify_document_task.delay(doc.id)

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

    @action(detail=False, methods=['post'], url_path='upload-url')
    def upload_url(self, request):
        """Return a presigned PUT URL for a quarantine document object."""
        from core.storage import generate_upload_url

        content_type = request.data.get('content_type') or 'application/octet-stream'
        filename = request.data.get('filename')
        family_id = getattr(request.user.family, 'id', None)
        key = build_quarantine_key(
            family_id,
            'documents',
            content_type,
            filename=filename,
        )
        put_url = generate_upload_url(key, content_type)
        return success_response(data={
            'upload_id': key.rsplit('/', 1)[-1].split('.', 1)[0],
            'upload_url': put_url,
            'raw_key': key,
            'expires_in': 3600,
        })

    def _validate_document_key(self, raw_key, family_id):
        if not is_valid_quarantine_key(raw_key, family_id, 'documents'):
            raise ValidationError({
                'raw_file_key': 'Document upload key is outside this family quarantine path.'
            })
