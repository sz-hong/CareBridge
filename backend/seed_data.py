"""
CareBridge 假資料填充腳本
為所有資料表各新增一筆（或多筆）範例資料
"""
import uuid
from datetime import date, timedelta
from decimal import Decimal

from django.utils import timezone

# ─── 1. Users ───────────────────────────────────────────────
from apps.auth_account.models import User

# 家屬（已有 test@carebridge.com，取出來用）
family_user = User.objects.filter(email='test@carebridge.com').first()
if not family_user:
    family_user = User.objects.create_user(
        email='test@carebridge.com', password='test1234',
        name='測試用戶', role='family_member', language='zh-TW',
    )
else:
    family_user.set_password('test1234')
    family_user.save()

# 看護
caregiver, _ = User.objects.get_or_create(
    email='rita@carebridge.com',
    defaults=dict(
        name='Rita Santos', role='caregiver', language='id',
        phone='0912111222',
    ),
)
caregiver.set_password('test1234')
caregiver.save()

# 長者
elder, _ = User.objects.get_or_create(
    email='elder@carebridge.com',
    defaults=dict(
        name='王爺爺', role='elder', language='zh-TW',
    ),
)
elder.set_password('test1234')
elder.save()

# 無家庭測試帳號 A：用來測試「建立新家庭」流程
no_family_a, _ = User.objects.get_or_create(
    email='creator@carebridge.com',
    defaults=dict(
        name='測試建立者', role='family_member', language='zh-TW',
    ),
)
no_family_a.set_password('test1234')
no_family_a.family = None
no_family_a.is_primary = False
no_family_a.save()

# 無家庭測試帳號 B：用來測試「加入家庭」流程
no_family_b, _ = User.objects.get_or_create(
    email='joiner@carebridge.com',
    defaults=dict(
        name='測試加入者', role='caregiver', language='zh-TW',
    ),
)
no_family_b.set_password('test1234')
no_family_b.family = None
no_family_b.is_primary = False
no_family_b.save()

print(f'✅ Users: {User.objects.count()} 筆')

# ─── 2. Family ──────────────────────────────────────────────
from apps.family.models import Family

family, _ = Family.objects.get_or_create(
    invite_code='202600',
    defaults=dict(
        name='王家', elder_name='王大明',
        elder_birth_date=date(1945, 3, 15),
        created_by=family_user,
    ),
)
# 將三個使用者都加入家庭
for u in [family_user, caregiver, elder]:
    u.family = family
    u.save(update_fields=['family'])
family_user.is_primary = True
family_user.save(update_fields=['is_primary'])

print(f'✅ Family: {Family.objects.count()} 筆')

# ─── 3. Chat + ChatMember + Message ─────────────────────────
from apps.chat.models import Chat, ChatMember, Message

chat, _ = Chat.objects.get_or_create(
    name='王家照護群',
    defaults=dict(type='group', family=family),
)
for u in [family_user, caregiver, elder]:
    ChatMember.objects.get_or_create(chat=chat, user=u)

msg, _ = Message.objects.get_or_create(
    chat=chat, sender=caregiver,
    defaults=dict(
        type='text',
        content='Kakek hari ini makan dengan baik',
        translations={'zh-TW': '爺爺今天吃得不錯', 'id': 'Kakek hari ini makan dengan baik'},
    ),
)

print(f'✅ Chat: {Chat.objects.count()} 筆, Message: {Message.objects.count()} 筆')

# ─── 4. BoardRequest (留言板) ────────────────────────────────
from apps.board.models import BoardRequest

BoardRequest.objects.get_or_create(
    family=family, requester=caregiver, category='food',
    defaults=dict(
        items=[
            {'name': 'Susu', 'name_translated': '牛奶', 'quantity': '2 盒'},
            {'name': 'Roti', 'name_translated': '麵包', 'quantity': '1 條'},
        ],
        note='Untuk sarapan kakek',
        note_translated='給爺爺當早餐',
        status='pending',
    ),
)

print(f'✅ BoardRequest: {BoardRequest.objects.count()} 筆')

# ─── 5. CareLog (照護日誌) ──────────────────────────────────
from apps.care_log.models import CareLog

now = timezone.now()

CareLog.objects.get_or_create(
    family=family, recorder=caregiver, type='vital',
    defaults=dict(
        content={
            'blood_pressure_systolic': 128,
            'blood_pressure_diastolic': 82,
            'blood_sugar': 5.8,
            'temperature': 36.5,
            'note': '狀況穩定',
        },
        timestamp=now - timedelta(hours=2),
    ),
)

care_log_med, _ = CareLog.objects.get_or_create(
    family=family, recorder=caregiver, type='medication',
    defaults=dict(
        content={
            'medication_name': 'Amlodipine 5mg',
            'dosage': '1 顆',
            'status': 'taken',
        },
        timestamp=now - timedelta(hours=3),
    ),
)

CareLog.objects.get_or_create(
    family=family, recorder=caregiver, type='meal',
    defaults=dict(
        content={
            'meal_type': 'breakfast',
            'description': '白粥、蒸蛋、菠菜',
            'description_translated': 'Bubur, telur kukus, bayam',
            'appetite': 'good',
        },
        timestamp=now - timedelta(hours=4),
    ),
)

print(f'✅ CareLog: {CareLog.objects.count()} 筆')

# ─── 6. Medication (藥物) ───────────────────────────────────
from apps.medication.models import Medication, MedicationConfirmation

med, _ = Medication.objects.get_or_create(
    family=family, name='Amlodipine 5mg',
    defaults=dict(
        name_translated={'zh-TW': '脈優 5mg', 'id': 'Amlodipine 5mg'},
        dosage='1 顆',
        frequency='daily',
        times=['08:00', '20:00'],
        instructions='飯後服用，注意低血壓',
        instructions_translated={'zh-TW': '飯後服用，注意低血壓', 'id': 'Diminum setelah makan'},
        start_date=date(2026, 1, 1),
        is_active=True,
        reminder_enabled=True,
        created_by=family_user,
    ),
)

# MedicationConfirmation
MedicationConfirmation.objects.get_or_create(
    medication=med, confirmed_by=caregiver, scheduled_time='08:00',
    defaults=dict(
        photo_url='https://example.com/med-photo.jpg',
        note='順利服藥',
        care_log=care_log_med,
    ),
)

print(f'✅ Medication: {Medication.objects.count()} 筆, Confirmation: {MedicationConfirmation.objects.count()} 筆')

# ─── 7. Expense (消費) ──────────────────────────────────────
from apps.expense.models import Expense

Expense.objects.get_or_create(
    family=family, recorder=caregiver, store_name='全聯福利中心',
    defaults=dict(
        date=date.today(),
        items=[
            {'name': '鮮奶', 'quantity': 2, 'unit_price': 75, 'total': 150, 'category': 'food'},
            {'name': '雞蛋', 'quantity': 1, 'unit_price': 89, 'total': 89, 'category': 'food'},
        ],
        total_amount=Decimal('239.00'),
        status='completed',
    ),
)

print(f'✅ Expense: {Expense.objects.count()} 筆')

# ─── 8. Leave (請假) ────────────────────────────────────────
from apps.leave.models import Leave

Leave.objects.get_or_create(
    family=family, applicant=caregiver, type='personal',
    defaults=dict(
        start_date=date.today() + timedelta(days=10),
        end_date=date.today() + timedelta(days=12),
        days=3,
        reason='Pulang kampung',
        reason_translated='返鄉探親',
        status='pending',
    ),
)

print(f'✅ Leave: {Leave.objects.count()} 筆')

# ─── 9. HealthData + HealthAlertThreshold + HealthAlert ─────
from apps.health.models import HealthData, HealthAlertThreshold, HealthAlert

HealthData.objects.get_or_create(
    family=family, type='heart_rate',
    recorded_at=now - timedelta(minutes=30),
    defaults=dict(
        value=Decimal('72.00'),
        unit='bpm',
    ),
)

HealthData.objects.get_or_create(
    family=family, type='blood_oxygen',
    recorded_at=now - timedelta(minutes=30),
    defaults=dict(
        value=Decimal('97.50'),
        unit='%',
    ),
)

HealthData.objects.get_or_create(
    family=family, type='step_count',
    recorded_at=now - timedelta(hours=1),
    defaults=dict(
        value=Decimal('2340'),
        unit='steps',
    ),
)

threshold, _ = HealthAlertThreshold.objects.get_or_create(
    family=family,
    defaults=dict(
        heart_rate_high=100,
        heart_rate_low=50,
        blood_oxygen_low=Decimal('93.0'),
        updated_by=family_user,
    ),
)

HealthAlert.objects.get_or_create(
    family=family, type='heart_rate',
    recorded_at=now - timedelta(days=1),
    defaults=dict(
        value=Decimal('112.00'),
        threshold=Decimal('100.00'),
        severity='warning',
    ),
)

print(f'✅ HealthData: {HealthData.objects.count()} 筆, Alert: {HealthAlert.objects.count()} 筆')

# ─── 10. Event (行事曆) ─────────────────────────────────────
from apps.calendar_event.models import Event

Event.objects.get_or_create(
    family=family, title='心臟科回診',
    defaults=dict(
        start_time=now + timedelta(days=5),
        end_time=now + timedelta(days=5, hours=1),
        location='台大醫院心臟科門診',
        type='medical',
        reminder_minutes=60,
        note='記得帶健保卡',
        source='manual',
        created_by=family_user,
    ),
)

Event.objects.get_or_create(
    family=family, title='物理治療復健',
    defaults=dict(
        start_time=now + timedelta(days=2),
        location='復健科',
        type='rehab',
        created_by=family_user,
    ),
)

print(f'✅ Event: {Event.objects.count()} 筆')

# ─── 11. Todo (代辦事項) ────────────────────────────────────
from apps.todo.models import Todo

Todo.objects.get_or_create(
    family=family, title='安排回診掛號（台大醫院心臟科）',
    defaults=dict(
        assignee=family_user,
        priority='high',
        status='pending',
        due_date=date.today() + timedelta(days=3),
        created_by=family_user,
    ),
)

Todo.objects.get_or_create(
    family=family, title='補購復健護具',
    defaults=dict(
        assignee=caregiver,
        priority='medium',
        status='pending',
        due_date=date.today() + timedelta(days=1),
        created_by=family_user,
    ),
)

print(f'✅ Todo: {Todo.objects.count()} 筆')

# ─── 12. Document (文件) ────────────────────────────────────
from apps.document.models import Document

Document.objects.get_or_create(
    family=family, title='長照保險單 2024',
    defaults=dict(
        category='insurance',
        file_url='https://example.com/docs/insurance-2024.pdf',
        file_size=2400000,
        mime_type='application/pdf',
        uploaded_by=family_user,
    ),
)

Document.objects.get_or_create(
    family=family, title='最新健康檢查報告',
    defaults=dict(
        category='medical',
        file_url='https://example.com/docs/health-report.pdf',
        file_size=5300000,
        mime_type='application/pdf',
        uploaded_by=family_user,
    ),
)

print(f'✅ Document: {Document.objects.count()} 筆')

# ─── 13. AIConversation ─────────────────────────────────────
from apps.ai_assistant.models import AIConversation

AIConversation.objects.get_or_create(
    family=family, user=family_user,
    defaults=dict(
        messages_history=[
            {'role': 'user', 'content': '請分析一下爺爺過去三天的血壓趨勢。'},
            {'role': 'assistant', 'content': '根據過去 72 小時的數據顯示，爺爺的血壓呈現小幅波動但總體趨於穩定。收縮壓在 128–135 mmHg 之間，舒張壓穩定在 78–82 mmHg。建議：當前狀態良好，請繼續保持低鹽飲食。'},
        ],
        tokens_used=350,
    ),
)

print(f'✅ AIConversation: {AIConversation.objects.count()} 筆')

# ─── 14. FirstAidDocument (急救文件，不含 embedding) ─────────
from apps.ai_assistant.models import FirstAidDocument

FirstAidDocument.objects.get_or_create(
    title='昏厥急救指南',
    defaults=dict(
        source='衛福部急救手冊',
        section='第三章 常見急症',
        content='1. 確認環境安全後，輕拍患者肩膀並呼喚。2. 撥打 119。3. 開始 CPR：按壓深度 5cm，速率 100–120 次/分。4. 使用 AED。',
    ),
)

print(f'✅ FirstAidDocument: {FirstAidDocument.objects.count()} 筆')

# ─── 15. SOSRecord ──────────────────────────────────────────
from apps.sos.models import SOSRecord

SOSRecord.objects.get_or_create(
    family=family, triggered_by=elder,
    defaults=dict(
        location={'latitude': 25.033, 'longitude': 121.565, 'accuracy': 10.0, 'address': '台北市中正區'},
        situation='爺爺在浴室跌倒',
        auto_call_119=True,
        notified_members=[
            {'id': str(family_user.id), 'notified_at': now.isoformat()},
            {'id': str(caregiver.id), 'notified_at': now.isoformat()},
        ],
        status='resolved',
        resolved_at=now - timedelta(hours=1),
    ),
)

print(f'✅ SOSRecord: {SOSRecord.objects.count()} 筆')

# ─── 16. Notification ───────────────────────────────────────
from apps.notification.models import Notification, Device

Notification.objects.get_or_create(
    user=family_user, type='health_alert',
    defaults=dict(
        title='心率異常警示',
        body='爺爺心率達到 112 bpm，超出正常範圍',
        data={'action': 'open_health_dashboard'},
        is_read=False,
    ),
)

Notification.objects.get_or_create(
    user=family_user, type='medication_reminder',
    defaults=dict(
        title='用藥提醒',
        body='下午 2:00 Amlodipine 5mg 服藥時間到',
        is_read=False,
    ),
)

Notification.objects.get_or_create(
    user=family_user, type='leave_request',
    defaults=dict(
        title='請假申請',
        body='Rita Santos 申請 4/20-4/22 事假，請審核',
        is_read=True,
    ),
)

# Device
Device.objects.get_or_create(
    user=family_user, device_token='fake-apns-token-for-testing-000',
    defaults=dict(
        platform='ios',
        device_name='iPhone 16 Pro',
        is_active=True,
    ),
)

print(f'✅ Notification: {Notification.objects.count()} 筆, Device: {Device.objects.count()} 筆')

print()
print('🎉 所有資料表假資料填充完成！')
