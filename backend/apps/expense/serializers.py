from rest_framework import serializers

from .models import Expense


class ExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = [
            'id', 'family', 'recorder', 'scan_id', 'store_name',
            'date', 'items', 'total_amount', 'image_url',
            'ocr_confidence', 'status', 'created_at', 'updated_at',
        ]
        read_only_fields = fields


class CreateExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = ['store_name', 'date', 'items', 'total_amount', 'image_url']


class ScanReceiptSerializer(serializers.Serializer):
    image_url = serializers.URLField(max_length=500)
