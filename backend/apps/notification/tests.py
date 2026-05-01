from django.test import SimpleTestCase, TestCase
from django.utils import timezone

from apps.auth_account.models import User
from apps.family.models import Family
from apps.medication.models import Medication
from apps.notification.models import Notification
from apps.notification.tasks import send_medication_reminders
from apps.notification.types import NotificationType


class NotificationTypeContractTests(SimpleTestCase):
    def test_supported_notification_types_are_centralized(self):
        self.assertEqual(
            set(NotificationType.values),
            {
                'health_alert',
                'medication_reminder',
                'medication_confirmed',
                'leave_request',
                'leave_status',
                'board_request',
                'board_approved',
                'expense_scanned',
                'sos',
                'sos_resolved',
                'event_reminder',
                'todo_assigned',
                'chat_message',
            },
        )


class MedicationReminderTaskTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='caregiver@example.com',
            password='password123',
            name='Caregiver',
            role=User.Role.CAREGIVER,
        )
        self.family = Family.objects.create(
            name='Reminder Family',
            elder_name='Elder',
            invite_code='333333',
            created_by=self.user,
        )
        self.user.family = self.family
        self.user.save(update_fields=['family'])

    def test_medication_reminder_task_uses_current_medication_times_field(self):
        current_time = timezone.localtime().strftime('%H:%M')
        medication = Medication.objects.create(
            family=self.family,
            created_by=self.user,
            name='Aspirin',
            dosage='100mg',
            frequency=Medication.Frequency.DAILY,
            times=[current_time],
            start_date=timezone.localdate(),
        )

        send_medication_reminders.run()

        notification = Notification.objects.get(user=self.user)
        self.assertEqual(notification.type, 'medication_reminder')
        self.assertEqual(notification.data['medication_id'], str(medication.id))
        self.assertEqual(notification.data['scheduled_time'], current_time)
