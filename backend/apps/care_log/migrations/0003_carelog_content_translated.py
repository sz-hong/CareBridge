from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('care_log', '0002_carelog_idx_carelog_family_time_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='carelog',
            name='content_translated',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
