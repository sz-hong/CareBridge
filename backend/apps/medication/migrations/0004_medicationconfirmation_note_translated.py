from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('medication', '0003_alter_medication_frequency_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='medicationconfirmation',
            name='note_translated',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
