from rest_framework import serializers

from apps.auth_account.serializers import UserSerializer
from .models import Todo


class TodoSerializer(serializers.ModelSerializer):
    assignee = UserSerializer(read_only=True)
    created_by = UserSerializer(read_only=True)

    class Meta:
        model = Todo
        fields = [
            'id', 'family', 'title', 'title_translated', 'assignee',
            'priority', 'status', 'due_date', 'completed_at', 'care_log',
            'created_by', 'created_at',
        ]
        read_only_fields = fields


class CreateTodoSerializer(serializers.ModelSerializer):
    assignee_id = serializers.UUIDField()

    class Meta:
        model = Todo
        fields = ['title', 'assignee_id', 'priority', 'due_date']
