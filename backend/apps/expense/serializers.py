from rest_framework import serializers

from core.storage import extract_key_from_url, generate_download_url
from .categories import normalize_expense_items
from .models import Expense


class ExpenseSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()
    has_image = serializers.SerializerMethodField()

    class Meta:
        model = Expense
        fields = [
            'id', 'family', 'recorder', 'scan_id', 'store_name',
            'date', 'items', 'total_amount', 'image_url', 'has_image',
            'ocr_confidence', 'status', 'deid_status', 'deid_findings',
            'deid_processed_at', 'created_at', 'updated_at',
        ]
        read_only_fields = fields

    def get_has_image(self, obj):
        return bool(obj.image_url)

    def get_image_url(self, obj):
        # Bucket is private (AWS_QUERYSTRING_AUTH=True), so the stored bare URL
        # has to be converted to a short-lived presigned GET. Doing that for
        # every row of `list` forces a SigV4 signing trip per expense as soon
        # as the user opens 消費 — multiply by N rows × multiple page visits
        # and it dominates the latency. Only resolve on `retrieve`; list
        # responses surface `has_image` so the client knows whether to bother
        # fetching the detail endpoint at all.
        if not obj.image_url:
            return None
        view = self.context.get('view')
        if getattr(view, 'action', None) != 'retrieve':
            return None
        key = extract_key_from_url(obj.image_url)
        if not key:
            return obj.image_url
        try:
            return generate_download_url(key)
        except Exception:
            return obj.image_url

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['items'] = normalize_expense_items(data.get('items'))
        return data


class CreateExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = [
            'store_name', 'date', 'items', 'total_amount', 'image_url',
            'raw_image_key',
        ]
        extra_kwargs = {
            'image_url': {'required': False, 'allow_null': True, 'allow_blank': True},
            'raw_image_key': {'required': False, 'allow_null': True, 'allow_blank': True},
        }

    def validate(self, attrs):
        if 'image_url' in self.initial_data:
            raise serializers.ValidationError({
                'image_url': 'Direct receipt image URLs are disabled. Upload to quarantine storage and send raw_image_key.'
            })
        if 'items' in attrs:
            attrs['items'] = normalize_expense_items(attrs.get('items'))
        return attrs


class ScanReceiptSerializer(serializers.Serializer):
    image_url = serializers.URLField(max_length=500, required=False)
    upload_id = serializers.CharField(max_length=100, required=False)
    raw_key = serializers.CharField(max_length=500, required=False)

    def validate(self, attrs):
        if 'image_url' in self.initial_data:
            raise serializers.ValidationError({
                'image_url': 'Direct receipt image URLs are disabled. Upload to quarantine storage and send raw_key.'
            })
        if not attrs.get('raw_key'):
            raise serializers.ValidationError({'raw_key': 'raw_key is required.'})
        return attrs
