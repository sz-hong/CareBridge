from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from core.responses import success_response

from apps.care_log.models import CareLog
from .models import Todo
from .serializers import CreateTodoSerializer, TodoSerializer


class TodoViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = TodoSerializer

    def get_queryset(self):
        qs = Todo.objects.filter(family=self.request.user.family)
        s = self.request.query_params.get('status')
        if s:
            qs = qs.filter(status=s)
        assignee = self.request.query_params.get('assignee')
        if assignee:
            qs = qs.filter(assignee_id=assignee)
        priority = self.request.query_params.get('priority')
        if priority:
            qs = qs.filter(priority=priority)
        return qs.select_related('assignee', 'created_by')

    def get_serializer_class(self):
        if self.action == 'create':
            return CreateTodoSerializer
        return TodoSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = TodoSerializer(page, many=True)
            paginated = self.get_paginated_response(serializer.data)
            return success_response(data=serializer.data, meta={
                'count': paginated.data['count'],
            })
        serializer = TodoSerializer(qs, many=True)
        return success_response(data=serializer.data)

    def create(self, request, *args, **kwargs):
        serializer = CreateTodoSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        todo = serializer.save(
            family=request.user.family,
            created_by=request.user,
            assignee_id=serializer.validated_data['assignee_id'],
        )
        return success_response(
            data=TodoSerializer(todo).data,
            status=status.HTTP_201_CREATED,
        )

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return success_response(data=TodoSerializer(instance).data)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        old_status = instance.status
        new_status = request.data.get('status', old_status)

        # Apply simple field updates
        for field in ('title', 'priority', 'due_date', 'status'):
            if field in request.data:
                setattr(instance, field, request.data[field])

        # Cross-module trigger: auto-create CareLog on completion
        if old_status != 'completed' and new_status == 'completed':
            instance.completed_at = timezone.now()
            care_log = CareLog.objects.create(
                family=instance.family,
                recorder=request.user,
                type=CareLog.Type.ACTIVITY,
                content={
                    'todo_id': str(instance.id),
                    'activity_type': f"待辦: {instance.title}",
                    'note': f"完成者：{request.user.name}",
                    'completed_by': str(request.user.id),
                },
                timestamp=timezone.now(),
            )
            instance.care_log = care_log

        instance.save()
        return success_response(data=TodoSerializer(instance).data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.delete()
        return success_response(status=status.HTTP_204_NO_CONTENT)
