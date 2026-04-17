from rest_framework import serializers

from core.storage import extract_key_from_url, generate_download_url
from .models import Expense


class ExpenseSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = Expense
        fields = [
            'id', 'family', 'recorder', 'scan_id', 'store_name',
            'date', 'items', 'total_amount', 'image_url',
            'ocr_confidence', 'status', 'created_at', 'updated_at',
        ]
        read_only_fields = fields

    def get_image_url(self, obj):
        # Bucket is private (AWS_QUERYSTRING_AUTH=True), so convert the stored
        # bare URL into a short-lived presigned GET URL for client display.
        if not obj.image_url:
            return None
        key = extract_key_from_url(obj.image_url)
        if not key:
            return obj.image_url
        try:
            return generate_download_url(key)
        except Exception:
            return obj.image_url


class CreateExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = ['store_name', 'date', 'items', 'total_amount', 'image_url']


class ScanReceiptSerializer(serializers.Serializer):
    image_url = serializers.URLField(max_length=500)
