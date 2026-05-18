from rest_framework import serializers


class AIChatSerializer(serializers.Serializer):
    message = serializers.CharField()
    conversation_id = serializers.UUIDField(required=False)


class AIChatResponseSerializer(serializers.Serializer):
    conversation_id = serializers.UUIDField()
    reply = serializers.CharField()
    tokens_used = serializers.IntegerField()


class CareAnalysisSerializer(serializers.Serializer):
    days = serializers.IntegerField(default=7, min_value=1, max_value=90)


class HandoverReportSerializer(serializers.Serializer):
    date = serializers.DateField(required=False)


class SubsidyFormSerializer(serializers.Serializer):
    form_type = serializers.ChoiceField(
        choices=[
            ('long_term_care', 'Long-term Care Subsidy'),
            ('disability', 'Disability Subsidy'),
            ('respite_care', 'Respite Care Subsidy'),
            ('uploaded_template', 'Uploaded Form Template'),
        ]
    )
    template_file = serializers.FileField(required=False, allow_empty_file=False)

    def validate(self, attrs):
        if attrs.get('form_type') == 'uploaded_template' and not attrs.get('template_file'):
            raise serializers.ValidationError({
                'template_file': 'A template file is required for uploaded_template.',
            })
        return attrs


class FirstAidQuerySerializer(serializers.Serializer):
    query = serializers.CharField()


class FirstAidScenarioSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    title = serializers.CharField()
    source = serializers.CharField()
    section = serializers.CharField(allow_null=True)
    content = serializers.CharField()
    relevance_score = serializers.FloatField(required=False)
