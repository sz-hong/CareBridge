from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('board', '0002_boardrequest_idx_board_family_status'),
    ]

    operations = [
        migrations.AddField(
            model_name='boardrequest',
            name='note_translations',
            field=models.JSONField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='boardrequest',
            name='reply_translations',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
