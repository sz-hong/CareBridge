from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.admin_api.models import AdminRequestLog


class Command(BaseCommand):
    help = 'Delete old admin request log rows.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--days',
            type=int,
            default=14,
            help='Keep logs newer than this many days. Default: 14.',
        )

    def handle(self, *args, **options):
        days = max(1, options['days'])
        cutoff = timezone.now() - timedelta(days=days)
        deleted, _details = AdminRequestLog.objects.filter(
            created_at__lt=cutoff
        ).delete()
        self.stdout.write(
            self.style.SUCCESS(f'Deleted {deleted} admin request log row(s).')
        )
