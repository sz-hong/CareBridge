from urllib.parse import urlparse

from django.conf import settings
from django.db import migrations, models


def normalize_existing_photo_values(apps, schema_editor):
    CareLog = apps.get_model('care_log', 'CareLog')
    bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', '')

    for care_log in CareLog.objects.exclude(photo_key__isnull=True).exclude(photo_key=''):
        value = care_log.photo_key
        if not value.startswith(('http://', 'https://')):
            continue

        key = urlparse(value).path.lstrip('/')
        if bucket and key.startswith(f'{bucket}/'):
            key = key[len(bucket) + 1:]
        care_log.photo_key = key or None
        care_log.save(update_fields=['photo_key'])


class Migration(migrations.Migration):

    dependencies = [
        ('care_log', '0003_carelog_content_translated'),
    ]

    operations = [
        migrations.RenameField(
            model_name='carelog',
            old_name='photo_url',
            new_name='photo_key',
        ),
        migrations.AlterField(
            model_name='carelog',
            name='photo_key',
            field=models.CharField(blank=True, max_length=500, null=True),
        ),
        migrations.RunPython(
            normalize_existing_photo_values,
            migrations.RunPython.noop,
        ),
    ]
