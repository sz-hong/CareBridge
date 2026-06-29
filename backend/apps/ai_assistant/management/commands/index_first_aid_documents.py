from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from apps.ai_assistant import views as ai_views
from apps.ai_assistant.models import FirstAidDocument


class Command(BaseCommand):
    help = 'Generate OpenAI embeddings for first-aid RAG documents.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Re-index every first-aid document even if the stored hash is current.',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=None,
            help='Maximum number of documents to index in this run.',
        )
        parser.add_argument(
            '--batch-size',
            type=int,
            default=50,
            help='Number of documents to send in each embeddings request.',
        )

    def handle(self, *args, **options):
        model_name = getattr(settings, 'OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small')
        expected_dimensions = getattr(settings, 'OPENAI_EMBEDDING_DIMENSIONS', 1536)
        batch_size = options['batch_size']
        if batch_size < 1:
            raise CommandError('--batch-size must be at least 1.')

        docs = list(FirstAidDocument.objects.all().order_by('title', 'id'))
        pending = [
            doc for doc in docs
            if options['force'] or doc.needs_embedding_refresh(model_name)
        ]
        if options['limit'] is not None:
            if options['limit'] < 0:
                raise CommandError('--limit must be 0 or greater.')
            pending = pending[:options['limit']]

        indexed = 0
        if pending:
            client = ai_views._get_client()
            for start in range(0, len(pending), batch_size):
                batch = pending[start:start + batch_size]
                response = client.embeddings.create(
                    model=model_name,
                    input=[doc.embedding_source_text() for doc in batch],
                )
                data = list(response.data)
                if len(data) != len(batch):
                    raise CommandError(
                        f'Embedding API returned {len(data)} vectors for {len(batch)} documents.'
                    )

                for doc, item in zip(batch, data):
                    embedding = list(item.embedding)
                    if len(embedding) != expected_dimensions:
                        raise CommandError(
                            'Embedding dimension mismatch for '
                            f'{doc.id}: expected {expected_dimensions}, got {len(embedding)}.'
                        )
                    doc.embedding = embedding
                    doc.embedding_model = model_name
                    doc.embedding_content_hash = doc.embedding_source_hash_value()
                    doc.embedded_at = timezone.now()
                    doc.save(update_fields=[
                        'embedding',
                        'embedding_model',
                        'embedding_content_hash',
                        'embedded_at',
                    ])
                    indexed += 1

        skipped = len(docs) - indexed
        self.stdout.write(
            self.style.SUCCESS(
                f'First-aid RAG indexing complete: total={len(docs)} '
                f'indexed={indexed} skipped={skipped}'
            )
        )
