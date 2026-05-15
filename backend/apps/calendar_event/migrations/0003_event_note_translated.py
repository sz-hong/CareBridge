from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('calendar_event', '0002_event_idx_event_family_time'),
    ]

    operations = [
        migrations.AddField(
            model_name='event',
            name='note_translated',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
