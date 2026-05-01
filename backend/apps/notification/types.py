from django.db import models


class NotificationType(models.TextChoices):
    HEALTH_ALERT = 'health_alert', 'Health alert'
    MEDICATION_REMINDER = 'medication_reminder', 'Medication reminder'
    MEDICATION_CONFIRMED = 'medication_confirmed', 'Medication confirmed'
    LEAVE_REQUEST = 'leave_request', 'Leave request'
    LEAVE_STATUS = 'leave_status', 'Leave status'
    BOARD_REQUEST = 'board_request', 'Board request'
    BOARD_APPROVED = 'board_approved', 'Board approved'
    EXPENSE_SCANNED = 'expense_scanned', 'Expense scanned'
    SOS = 'sos', 'SOS'
    SOS_RESOLVED = 'sos_resolved', 'SOS resolved'
    EVENT_REMINDER = 'event_reminder', 'Event reminder'
    TODO_ASSIGNED = 'todo_assigned', 'Todo assigned'
    CHAT_MESSAGE = 'chat_message', 'Chat message'
