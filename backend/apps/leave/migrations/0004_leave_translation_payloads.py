from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('leave', '0003_leavevote'),
    ]

    operations = [
        migrations.AddField(
            model_name='leave',
            name='reason_translations',
            field=models.JSONField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='leave',
            name='reply_translations',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
