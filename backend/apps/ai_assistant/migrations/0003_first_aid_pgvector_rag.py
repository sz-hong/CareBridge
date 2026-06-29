import json

from django.db import migrations, models
from pgvector.django import HnswIndex, VectorExtension, VectorField


def copy_legacy_embeddings(apps, schema_editor):
    FirstAidDocument = apps.get_model('ai_assistant', 'FirstAidDocument')
    for doc in FirstAidDocument.objects.exclude(legacy_embedding__isnull=True).exclude(legacy_embedding=''):
        try:
            vector = json.loads(doc.legacy_embedding)
        except (TypeError, json.JSONDecodeError):
            continue

        if not isinstance(vector, list) or len(vector) != 1536:
            continue

        try:
            doc.embedding = [float(value) for value in vector]
        except (TypeError, ValueError):
            continue
        doc.save(update_fields=['embedding'])


def create_hnsw_index(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    schema_editor.execute(
        """
        CREATE INDEX IF NOT EXISTS first_aid_embed_hnsw
        ON first_aid_document
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64)
        """
    )


def drop_hnsw_index(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    schema_editor.execute('DROP INDEX IF EXISTS first_aid_embed_hnsw')


class Migration(migrations.Migration):

    dependencies = [
        ('ai_assistant', '0002_initial'),
    ]

    operations = [
        VectorExtension(),
        migrations.RenameField(
            model_name='firstaiddocument',
            old_name='embedding',
            new_name='legacy_embedding',
        ),
        migrations.AddField(
            model_name='firstaiddocument',
            name='embedding',
            field=VectorField(blank=True, dimensions=1536, null=True),
        ),
        migrations.AddField(
            model_name='firstaiddocument',
            name='embedding_model',
            field=models.CharField(blank=True, default='', max_length=100),
        ),
        migrations.AddField(
            model_name='firstaiddocument',
            name='embedding_content_hash',
            field=models.CharField(blank=True, default='', max_length=64),
        ),
        migrations.AddField(
            model_name='firstaiddocument',
            name='embedded_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.RunPython(copy_legacy_embeddings, migrations.RunPython.noop),
        migrations.RemoveField(
            model_name='firstaiddocument',
            name='legacy_embedding',
        ),
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(create_hnsw_index, drop_hnsw_index),
            ],
            state_operations=[
                migrations.AddIndex(
                    model_name='firstaiddocument',
                    index=HnswIndex(
                        fields=['embedding'],
                        m=16,
                        ef_construction=64,
                        opclasses=['vector_cosine_ops'],
                        name='first_aid_embed_hnsw',
                    ),
                ),
            ],
        ),
    ]
