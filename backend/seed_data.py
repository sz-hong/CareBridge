"""
CareBridge 資料庫種子腳本
============================================================================

⚙️  執行方式
    docker exec -w /app -e DJANGO_SETTINGS_MODULE=carebridge_api.settings \\
        docker-web-1 python -c "exec(open('/app/seed_data.py').read())"

    或在 host:
        cd backend && python manage.py shell < seed_data.py

🔄  每次執行都會：
    1) **完全清空** 下面列出的 table（用依存順序刪除）
    2) **重新建立** 所有測試帳號（保證每次密碼都對得起來）
    3) **填入完整範例資料**，覆蓋目前所有功能模組

🔐  測試帳號（密碼一律：test1234）
    ┌──────────────────────────────┬─────────────┬──────────┬──────────────┐
    │ Email                        │ Role        │ 家庭     │ 用途         │
    ├──────────────────────────────┼─────────────┼──────────┼──────────────┤
    │ hank@carebridge.com          │ family      │ 王家     │ 主測試家屬   │
    │ rita@carebridge.com          │ caregiver   │ 王家     │ 看護（印尼） │
    │ ming@carebridge.com          │ family      │ 王家     │ 第二位家屬   │
    │ elder@carebridge.com         │ elder       │ 王家     │ 長者         │
    │ creator@carebridge.com       │ family      │ —        │ 測「建立家庭」│
    │ joiner@carebridge.com        │ caregiver   │ —        │ 測「加入家庭」│
    └──────────────────────────────┴─────────────┴──────────┴──────────────┘

🏠  家庭邀請碼：202600（王家）
============================================================================
"""

import os
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal

# 允許用 `python -c "exec(open('seed_data.py').read())"` 直接執行
# （不必透過 manage.py shell）。如果是經由 shell pipe 進來，apps 已載入，
# django.setup() 會是 no-op；獨立執行時才真正 setup。
import django
from django.apps import apps as django_apps
if not django_apps.ready:
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'carebridge_api.settings')
    django.setup()

from django.utils import timezone


# ============================================================================
# 0. WIPE — 依外鍵反向順序清空所有 table
# ============================================================================
print('🧹 清空現有資料...')

# Notifications / push
from apps.notification.models import Notification, Device
Device.objects.all().delete()
Notification.objects.all().delete()

# SOS
from apps.sos.models import SOSRecord
SOSRecord.objects.all().delete()

# AI
from apps.ai_assistant.models import AIConversation, FirstAidDocument
AIConversation.objects.all().delete()
FirstAidDocument.objects.all().delete()

# 文件 / 行事曆 / 待辦
from apps.document.models import Document
from apps.calendar_event.models import Event
from apps.todo.models import Todo
Document.objects.all().delete()
Todo.objects.all().delete()
Event.objects.all().delete()  # 注意：Leave 透過 calendar_event FK 連到此表

# 健康
from apps.health.models import HealthData, HealthAlertThreshold, HealthAlert
HealthAlert.objects.all().delete()
HealthAlertThreshold.objects.all().delete()
HealthData.objects.all().delete()

# 請假（先 vote 再 leave，因為 vote FK → leave）
from apps.leave.models import Leave, LeaveVote
LeaveVote.objects.all().delete()
Leave.objects.all().delete()

# 消費
from apps.expense.models import Expense
Expense.objects.all().delete()

# 用藥
from apps.medication.models import Medication, MedicationConfirmation
MedicationConfirmation.objects.all().delete()
Medication.objects.all().delete()

# 照護日誌
from apps.care_log.models import CareLog
CareLog.objects.all().delete()

# 留言板
from apps.board.models import BoardRequest
BoardRequest.objects.all().delete()

# 聊天
from apps.chat.models import Chat, ChatMember, Message
Message.objects.all().delete()
ChatMember.objects.all().delete()
Chat.objects.all().delete()

# 家庭
from apps.family.models import Family
Family.objects.all().delete()

# 使用者放最後（其他表都 FK 過來）
from apps.auth_account.models import User
User.objects.all().delete()

print('   ✓ 所有資料表已清空')
print()


# ============================================================================
# 1. Users — 測試帳號（密碼統一 test1234）
# ============================================================================
print('👥 建立使用者...')

PASSWORD = 'test1234'

# 王家 — 主測試家屬（FE 主要登入帳號）
hank = User.objects.create_user(
    email='hank@carebridge.com', password=PASSWORD,
    name='Hank Chen', role='family_member', language='zh-TW',
    phone='0912345678',
)

# 王家 — 看護，預設語言印尼文（測試聊天翻譯）
rita = User.objects.create_user(
    email='rita@carebridge.com', password=PASSWORD,
    name='Rita Santos', role='caregiver', language='id',
    phone='0912111222',
)

# 王家 — 第二位家屬（測試請假投票需要 ≥1 家屬）
ming = User.objects.create_user(
    email='ming@carebridge.com', password=PASSWORD,
    name='林小明', role='family_member', language='zh-TW',
    phone='0912333444',
)

# 王家 — 長者
elder = User.objects.create_user(
    email='elder@carebridge.com', password=PASSWORD,
    name='王爺爺', role='elder', language='zh-TW',
)

# 無家庭 A — 用來測「建立新家庭」流程
creator = User.objects.create_user(
    email='creator@carebridge.com', password=PASSWORD,
    name='測試建立者', role='family_member', language='zh-TW',
)

# 無家庭 B — 用來測「加入家庭」流程
joiner = User.objects.create_user(
    email='joiner@carebridge.com', password=PASSWORD,
    name='測試加入者', role='caregiver', language='zh-TW',
)

print(f'   ✓ User: {User.objects.count()} 筆')


# ============================================================================
# 2. Family — 王家（邀請碼 202600）
# ============================================================================
print('🏠 建立家庭...')

family = Family.objects.create(
    name='王家',
    elder_name='王大明',
    elder_birth_date=date(1945, 3, 15),
    invite_code='202600',
    created_by=hank,
)

# 把王家成員都歸入這個家庭
for u in (hank, rita, ming, elder):
    u.family = family
    u.save(update_fields=['family'])

# 創建者標記為 primary
hank.is_primary = True
hank.save(update_fields=['is_primary'])

print(f'   ✓ Family: {Family.objects.count()} 筆，成員 {family.members.count()} 位')


# ============================================================================
# 3. Chat 預備 — 先建立 chat / 成員，但訊息留到 Leave/Board 建好後再灌入，
#    確保 chat card 的內容（日期、品項）與後端真實資料一致
# ============================================================================
print('💬 建立聊天室...')

now = timezone.now()

chat = Chat.objects.create(
    type='group',
    name='王家照護群',
    family=family,
)

# 全家庭成員都加入聊天室（與 enroll_user_in_family_chats 邏輯一致）
for u in (hank, rita, ming, elder):
    ChatMember.objects.create(chat=chat, user=u)

# 純文字訊息 — 看護回報，自動翻譯到全家屬語系
Message.objects.create(
    chat=chat, sender=rita, type='text', message_type='text',
    content='Kakek hari ini makan dengan baik',
    translations={
        'id':    'Kakek hari ini makan dengan baik',
        'zh-TW': '爺爺今天吃得不錯',
        'vi':    'Hôm nay ông ăn uống tốt',
        'tl':    'Ang lolo ay kumain nang mabuti ngayon',
    },
    sent_at=now - timedelta(hours=2),
)

Message.objects.create(
    chat=chat, sender=hank, type='text', message_type='text',
    content='謝謝你照顧爺爺',
    translations={
        'zh-TW': '謝謝你照顧爺爺',
        'id':    'Terima kasih sudah merawat kakek',
        'vi':    'Cảm ơn đã chăm sóc ông',
        'tl':    'Salamat sa pag-aalaga sa lolo',
    },
    sent_at=now - timedelta(hours=1, minutes=50),
)

# 卡片訊息（採購 / 請假）暫不建立——等 BoardRequest 跟 Leave 建好後，再用
# 它們的真實 id 跟 dates 一起補上，避免 hardcoded 文字跟 detail 頁日期對不上。

print(f'   ✓ Chat: {Chat.objects.count()}, Message: {Message.objects.count()}')


# ============================================================================
# 4. BoardRequest — 採購需求（不同狀態各一筆）
# ============================================================================
print('🛒 建立採購需求...')

# 留一筆 reference 給 chat 卡片用
purchase_for_card = BoardRequest.objects.create(
    family=family, requester=rita,
    category='daily',
    items=[
        {'name': 'Popok dewasa', 'name_translated': '成人紙尿褲', 'quantity': '1 包', 'estimated_cost': 850},
    ],
    note='Untuk kakek pakai sehari-hari, pilih ukuran L',
    note_translated='給王爺爺日用，請選 L 尺寸有透氣材質的',
    status='pending',
)

BoardRequest.objects.create(
    family=family, requester=rita,
    category='medical',
    items=[
        {'name': 'Amlodipine 5mg', 'quantity': '1 瓶', 'estimated_cost': 1200},
    ],
    note='剩約 3 天的量，需要補貨。處方藥需到藥局領',
    status='approved',
    reviewed_by=hank,
)

BoardRequest.objects.create(
    family=family, requester=rita,
    category='food',
    items=[
        {'name': 'Oatmeal', 'name_translated': '燕麥片', 'quantity': '1 罐', 'estimated_cost': 320},
    ],
    note='無糖那種，王爺爺早餐用',
    status='pending',
)

print(f'   ✓ BoardRequest: {BoardRequest.objects.count()} 筆')


# ============================================================================
# 5. CareLog — 照護日誌（生命徵象 / 用藥 / 飲食 / 活動 4 類各一）
# ============================================================================
print('📝 建立照護日誌...')

# 生命徵象
CareLog.objects.create(
    family=family, recorder=rita, type='vital',
    content={
        'blood_pressure_systolic': 128,
        'blood_pressure_diastolic': 82,
        'blood_sugar': 5.8,
        'temperature': 36.5,
        'note': '狀況穩定',
    },
    timestamp=now - timedelta(hours=2),
)

# 用藥（後續被 MedicationConfirmation 連結回此 log）
care_log_med = CareLog.objects.create(
    family=family, recorder=rita, type='medication',
    content={
        'medication_name': 'Amlodipine 5mg',
        'dosage': '1 顆',
        'status': 'taken',
        'scheduled_time': '08:00',
    },
    timestamp=now - timedelta(hours=3),
)

# 飲食
CareLog.objects.create(
    family=family, recorder=rita, type='meal',
    content={
        'meal_type': 'breakfast',
        'description': '白粥、蒸蛋、菠菜',
        'description_translated': 'Bubur, telur kukus, bayam',
        'appetite': 'good',
    },
    timestamp=now - timedelta(hours=4),
)

# 活動（這類也是 todo 完成時 backend 自動寫入的格式）
CareLog.objects.create(
    family=family, recorder=rita, type='activity',
    content={
        'activity_type': '陪同散步',
        'duration_minutes': 30,
        'note': '在公園走了約 1 公里',
    },
    timestamp=now - timedelta(hours=5),
)

print(f'   ✓ CareLog: {CareLog.objects.count()} 筆')


# ============================================================================
# 6. Medication + MedicationConfirmation
# ============================================================================
print('💊 建立用藥...')

today = timezone.localdate()

# 長期服用，無結束日（測試「無結束」accordion 顯示）
med_metformin = Medication.objects.create(
    family=family,
    name='Metformin 500mg',
    name_translated={'zh-TW': '糖必鎮 500mg', 'id': 'Metformin 500mg'},
    dosage='1 顆',
    frequency='twice_daily',
    times=['08:00', '20:00'],
    instructions='隨餐服用',
    instructions_translated={'zh-TW': '隨餐服用', 'id': 'Diminum saat makan'},
    start_date=today - timedelta(days=45),
    end_date=None,
    is_active=True,
    reminder_enabled=True,
    created_by=hank,
)

# 有結束日（accordion 應顯示「結束服用日」）
med_amlodipine = Medication.objects.create(
    family=family,
    name='Amlodipine 5mg',
    name_translated={'zh-TW': '安壓凝錠 5mg', 'id': 'Amlodipine 5mg'},
    dosage='1 顆',
    frequency='daily',
    times=['08:00'],
    instructions='飯後服用，避免葡萄柚汁',
    start_date=today - timedelta(days=20),
    end_date=today + timedelta(days=60),
    is_active=True,
    reminder_enabled=True,
    created_by=hank,
)

# 短期療程（即將結束）
Medication.objects.create(
    family=family,
    name='Aspirin 100mg',
    name_translated={'zh-TW': '阿斯匹靈 100mg', 'id': 'Aspirin 100mg'},
    dosage='1 顆',
    frequency='daily',
    times=['09:00'],
    instructions='預防心血管疾病',
    start_date=today - timedelta(days=10),
    end_date=today + timedelta(days=20),
    is_active=True,
    reminder_enabled=True,
    created_by=hank,
)

# 已結束療程（測試 backend 過期過濾，FE 不應該看到）
Medication.objects.create(
    family=family,
    name='Antibiotic 500mg (已結束)',
    dosage='1 顆',
    frequency='thrice_daily',
    times=['08:00', '14:00', '20:00'],
    instructions='療程結束',
    start_date=today - timedelta(days=20),
    end_date=today - timedelta(days=3),
    is_active=True,
    created_by=hank,
)

# 今日服藥確認紀錄
MedicationConfirmation.objects.create(
    medication=med_amlodipine,
    confirmed_by=rita,
    scheduled_time='08:00',
    note='順利服藥',
    care_log=care_log_med,
)

print(f'   ✓ Medication: {Medication.objects.count()}, Confirmation: {MedicationConfirmation.objects.count()}')


# ============================================================================
# 7. Expense — 消費記錄（含 image_url 模擬上傳收據後的紀錄）
# ============================================================================
print('💰 建立消費紀錄...')

Expense.objects.create(
    family=family, recorder=rita,
    store_name='全聯福利中心',
    date=today,
    items=[
        {'name': '鮮奶', 'quantity': 2, 'unit_price': 75, 'total': 150, 'category': 'food'},
        {'name': '雞蛋', 'quantity': 1, 'unit_price': 89, 'total': 89, 'category': 'food'},
    ],
    total_amount=Decimal('239.00'),
    image_url='http://localhost:9000/carebridge-storage/receipts/sample/sample-1.jpg',
    status='completed',
)

Expense.objects.create(
    family=family, recorder=rita,
    store_name='杏一藥局',
    date=today - timedelta(days=2),
    items=[
        {'name': '處方藥', 'quantity': 1, 'unit_price': 850, 'total': 850, 'category': 'medical'},
    ],
    total_amount=Decimal('850.00'),
    status='completed',
)

Expense.objects.create(
    family=family, recorder=rita,
    store_name='屈臣氏',
    date=today - timedelta(days=5),
    items=[
        {'name': '成人紙尿褲', 'quantity': 1, 'unit_price': 850, 'total': 850, 'category': 'daily'},
    ],
    total_amount=Decimal('850.00'),
    status='completed',
)

print(f'   ✓ Expense: {Expense.objects.count()} 筆')


# ============================================================================
# 8. Leave + LeaveVote — 涵蓋 pending / 投票中 / 已通過 / 已拒絕
# ============================================================================
print('📋 建立請假申請與投票...')

# 8a. Pending（無投票）— 之後會連結到 chat 卡片
leave_pending = Leave.objects.create(
    family=family, applicant=rita,
    type='personal',
    start_date=today + timedelta(days=7),
    end_date=today + timedelta(days=8),
    days=2,
    reason='Pulang kampung urusan keluarga',
    reason_translated='返鄉處理家中事務',
    status='pending',
)

# 8b. Pending — 已有部分投票，等其他家屬
leave_voting = Leave.objects.create(
    family=family, applicant=rita,
    type='sick',
    start_date=today + timedelta(days=14),
    end_date=today + timedelta(days=14),
    days=1,
    reason='Operasi gigi',
    reason_translated='牙科手術',
    status='pending',
)
LeaveVote.objects.create(
    leave=leave_voting, member=hank, member_name=hank.name,
    is_available=True,
)
# 林小明還沒投，狀態維持 pending

# 8c. 已通過 — 全部家屬都有空，狀態翻為 approved 並自動建 Event
leave_approved = Leave.objects.create(
    family=family, applicant=rita,
    type='personal',
    start_date=today + timedelta(days=21),
    end_date=today + timedelta(days=22),
    days=2,
    reason='Cuti pribadi',
    reason_translated='私人假',
    status='approved',
    reviewed_by=hank,
    reviewed_at=now,
)
LeaveVote.objects.create(
    leave=leave_approved, member=hank, member_name=hank.name,
    is_available=True,
)
LeaveVote.objects.create(
    leave=leave_approved, member=ming, member_name=ming.name,
    is_available=True,
)
# 對應的 Event 在下面 Section 11 建立並回填 calendar_event

# 8d. 已拒絕 — 全部家屬都沒空
leave_rejected = Leave.objects.create(
    family=family, applicant=rita,
    type='personal',
    start_date=today + timedelta(days=3),
    end_date=today + timedelta(days=3),
    days=1,
    reason='Acara teman',
    reason_translated='朋友聚會',
    status='rejected',
    reviewed_by=hank,
    reviewed_at=now,
)
LeaveVote.objects.create(
    leave=leave_rejected, member=hank, member_name=hank.name,
    is_available=False,
)
LeaveVote.objects.create(
    leave=leave_rejected, member=ming, member_name=ming.name,
    is_available=False,
)

print(f'   ✓ Leave: {Leave.objects.count()}, LeaveVote: {LeaveVote.objects.count()}')


# ============================================================================
# 8.5  補上聊天室的卡片訊息（用 BoardRequest / Leave 真實資料）
# ============================================================================
print('💬 補上請假/採購卡片訊息...')


def _format_md(d):
    return f'{d.month}/{d.day}'


# 採購卡片 — content 含品項名，reference_id 指向真實 BoardRequest
purchase_item_name = (
    purchase_for_card.items[0].get('name_translated')
    or purchase_for_card.items[0].get('name')
    or '未命名品項'
)
Message.objects.create(
    chat=chat, sender=rita, type='text',
    message_type='purchase_request',
    reference_id=purchase_for_card.id,
    content=f'📦 採購需求：{purchase_item_name}',
    sent_at=now - timedelta(hours=1, minutes=20),
)

# 請假卡片 — 假別 + 真實日期，reference_id 指向 leave_pending
leave_type_label = {
    'personal':  '事假',
    'sick':      '病假',
    'emergency': '緊急假',
}.get(leave_pending.type, leave_pending.type)

leave_card_text = (
    f'📋 請假申請：{leave_type_label} '
    f'{_format_md(leave_pending.start_date)}–{_format_md(leave_pending.end_date)}'
)
Message.objects.create(
    chat=chat, sender=rita, type='text',
    message_type='leave_request',
    reference_id=leave_pending.id,
    content=leave_card_text,
    sent_at=now - timedelta(hours=1),
)

print(f'   ✓ Message 卡片補完，聊天室訊息共 {Message.objects.count()} 則')


# ============================================================================
# 9. HealthData / HealthAlertThreshold / HealthAlert
# ============================================================================
print('❤️  建立健康資料...')

# 即時數值（FE 健康監測 dashboard 抓最近一筆）
HealthData.objects.create(
    family=family, type='heart_rate',
    value=Decimal('72.00'), unit='bpm',
    recorded_at=now - timedelta(minutes=30),
)
HealthData.objects.create(
    family=family, type='blood_oxygen',
    value=Decimal('97.50'), unit='%',
    recorded_at=now - timedelta(minutes=30),
)
HealthData.objects.create(
    family=family, type='step_count',
    value=Decimal('2340'), unit='steps',
    recorded_at=now - timedelta(hours=1),
)
HealthData.objects.create(
    family=family, type='blood_pressure_systolic',
    value=Decimal('128'), unit='mmHg',
    recorded_at=now - timedelta(hours=2),
)
HealthData.objects.create(
    family=family, type='blood_pressure_diastolic',
    value=Decimal('82'), unit='mmHg',
    recorded_at=now - timedelta(hours=2),
)

# 警戒值（家屬可在 FE 設定）
HealthAlertThreshold.objects.create(
    family=family,
    heart_rate_high=100,
    heart_rate_low=50,
    blood_oxygen_low=Decimal('93.0'),
    updated_by=hank,
)

# 過去發生過的警示（FE 異常紀錄列表）
HealthAlert.objects.create(
    family=family, type='heart_rate',
    value=Decimal('112.00'), threshold=Decimal('100.00'),
    severity='warning',
    recorded_at=now - timedelta(days=1),
)
HealthAlert.objects.create(
    family=family, type='blood_oxygen',
    value=Decimal('92.00'), threshold=Decimal('93.00'),
    severity='warning',
    recorded_at=now - timedelta(days=2),
)

print(f'   ✓ HealthData: {HealthData.objects.count()}, Alert: {HealthAlert.objects.count()}')


# ============================================================================
# 10. Event — 行事曆（含手動建立 + 由 leave 自動建立）
# ============================================================================
print('📅 建立行事曆事件...')


def aware(d, hour, minute=0):
    """組合台北時區的 datetime（避免 naive datetime warning）"""
    return timezone.make_aware(
        datetime.combine(d, datetime.min.time().replace(hour=hour, minute=minute))
    )


# 手動行程
Event.objects.create(
    family=family, created_by=hank,
    title='心臟科回診',
    type='medical', source='manual',
    start_time=aware(today + timedelta(days=5), 9),
    end_time=aware(today + timedelta(days=5), 10),
    location='台大醫院心臟科門診',
    reminder_minutes=60,
    note='記得帶健保卡',
)
Event.objects.create(
    family=family, created_by=hank,
    title='物理治療復健',
    type='rehab', source='manual',
    start_time=aware(today + timedelta(days=2), 14),
    end_time=aware(today + timedelta(days=2), 15),
    location='康寧復健診所',
)
Event.objects.create(
    family=family, created_by=hank,
    title='家庭聚餐',
    type='personal', source='manual',
    start_time=aware(today + timedelta(days=10), 18),
    end_time=aware(today + timedelta(days=10), 20),
    location='家裡',
)

# 今日的行程（FE 主頁「今日行程」row 會顯示）
Event.objects.create(
    family=family, created_by=hank,
    title='量血壓',
    type='medical', source='manual',
    start_time=aware(today, 9),
    end_time=aware(today, 9, 30),
    location='家裡',
    reminder_minutes=15,
)
Event.objects.create(
    family=family, created_by=hank,
    title='陪王爺爺散步',
    type='personal', source='manual',
    start_time=aware(today, 16, 30),
    end_time=aware(today, 17, 30),
    location='附近公園',
)

# 由 leave 通過後自動建立的 event（與 _ensure_calendar_event 邏輯一致）
leave_event = Event.objects.create(
    family=family, created_by=hank,
    title=f'{leave_approved.get_type_display()} Leave - {rita.name}',
    type='leave', source='leave',
    source_id=leave_approved.id,
    start_time=aware(leave_approved.start_date, 0),
    end_time=timezone.make_aware(
        datetime.combine(leave_approved.end_date,
                         datetime.max.time().replace(microsecond=0))
    ),
    note=leave_approved.reason,
)
leave_approved.calendar_event = leave_event
leave_approved.save(update_fields=['calendar_event'])

print(f'   ✓ Event: {Event.objects.count()} 筆')


# ============================================================================
# 11. Todo — 代辦事項（pending / completed 各一）
# ============================================================================
print('✅ 建立代辦事項...')

Todo.objects.create(
    family=family, created_by=hank, assignee=hank,
    title='安排回診掛號（台大醫院心臟科）',
    priority='high', status='pending',
    due_date=today + timedelta(days=3),
)
Todo.objects.create(
    family=family, created_by=hank, assignee=rita,
    title='補購復健護具',
    priority='medium', status='pending',
    due_date=today + timedelta(days=1),
)

# 今日待辦（FE 主頁「今日待辦」會顯示）
Todo.objects.create(
    family=family, created_by=hank, assignee=hank,
    title='帶王爺爺去公園散步',
    priority='medium', status='pending',
    due_date=today,
)
Todo.objects.create(
    family=family, created_by=hank, assignee=rita,
    title='購買降血壓藥（剩 3 天）',
    priority='high', status='pending',
    due_date=today,
)

# 已完成 — 連結到照護日誌（與後端 update_todo 自動建 CareLog 的邏輯一致）
todo_done = Todo.objects.create(
    family=family, created_by=hank, assignee=rita,
    title='幫王爺爺剪指甲',
    priority='low', status='completed',
    due_date=today - timedelta(days=1),
    completed_at=now - timedelta(hours=6),
)

print(f'   ✓ Todo: {Todo.objects.count()} 筆')


# ============================================================================
# 12. Document — 文件管理
# ============================================================================
print('📄 建立文件...')

Document.objects.create(
    family=family, uploaded_by=hank,
    title='長照保險單 2024',
    category='insurance',
    file_url='https://example.com/docs/insurance-2024.pdf',
    file_size=2_400_000,
    mime_type='application/pdf',
)
Document.objects.create(
    family=family, uploaded_by=hank,
    title='最新健康檢查報告',
    category='medical',
    file_url='https://example.com/docs/health-report.pdf',
    file_size=5_300_000,
    mime_type='application/pdf',
)
Document.objects.create(
    family=family, uploaded_by=hank,
    title='身分證影本',
    category='identity',
    file_url='https://example.com/docs/id-card.jpg',
    file_size=850_000,
    mime_type='image/jpeg',
)

print(f'   ✓ Document: {Document.objects.count()} 筆')


# ============================================================================
# 13. AIConversation — AI 助理對話記錄
# ============================================================================
print('🤖 建立 AI 對話...')

AIConversation.objects.create(
    family=family, user=hank,
    messages_history=[
        {'role': 'user', 'content': '請分析一下爺爺過去三天的血壓趨勢。'},
        {'role': 'assistant', 'content': (
            '根據過去 72 小時的數據顯示，爺爺的血壓呈現小幅波動但總體趨於穩定。'
            '收縮壓在 128–135 mmHg 之間，舒張壓穩定在 78–82 mmHg。'
            '建議：當前狀態良好，請繼續保持低鹽飲食。'
        )},
    ],
    tokens_used=350,
)

print(f'   ✓ AIConversation: {AIConversation.objects.count()} 筆')


# ============================================================================
# 14. FirstAidDocument — 急救手冊（RAG 知識庫，省略 embedding）
# ============================================================================
print('🚑 建立急救手冊...')

FirstAidDocument.objects.create(
    title='昏厥急救指南',
    source='衛福部急救手冊',
    section='第三章 常見急症',
    content=(
        '1. 確認環境安全後，輕拍患者肩膀並呼喚。'
        '2. 撥打 119。'
        '3. 開始 CPR：按壓深度 5cm，速率 100–120 次/分。'
        '4. 使用 AED。'
    ),
)
FirstAidDocument.objects.create(
    title='跌倒處置',
    source='衛福部急救手冊',
    section='第二章 居家意外',
    content=(
        '1. 不要立刻扶起，先評估意識與疼痛部位。'
        '2. 若懷疑骨折或頭部撞擊，撥打 119。'
        '3. 若意識清楚但無明顯傷害，協助慢慢起身。'
    ),
)
FirstAidDocument.objects.create(
    title='中風 FAST 評估',
    source='臺灣腦中風學會',
    section='第一章 心血管急症',
    content=(
        'F (Face) 臉歪嘴斜；'
        'A (Arm) 單手無力；'
        'S (Speech) 口齒不清；'
        'T (Time) 立刻撥 119、記下發作時間。'
    ),
)

print(f'   ✓ FirstAidDocument: {FirstAidDocument.objects.count()} 筆')


# ============================================================================
# 15. SOSRecord — 緊急求助
# ============================================================================
print('🆘 建立 SOS 紀錄...')

# 已解除的歷史紀錄（FE 列表會顯示）
SOSRecord.objects.create(
    family=family, triggered_by=elder,
    location={
        'latitude': 25.033, 'longitude': 121.565,
        'accuracy': 10.0, 'address': '台北市中正區',
    },
    situation='爺爺在浴室跌倒',
    auto_call_119=True,
    notified_members=[
        {'id': str(hank.id), 'notified_at': now.isoformat()},
        {'id': str(rita.id), 'notified_at': now.isoformat()},
    ],
    status='resolved',
    resolved_at=now - timedelta(hours=1),
)

print(f'   ✓ SOSRecord: {SOSRecord.objects.count()} 筆')


# ============================================================================
# 16. Notification + Device
# ============================================================================
print('🔔 建立通知與裝置...')

# 各種類型的通知（NotificationType enum 全部覆蓋一遍）
notifications = [
    ('health_alert',         '心率異常警示',  '爺爺心率達到 112 bpm，超出正常範圍',   False),
    ('medication_reminder',  '用藥提醒',     '下午 2:00 Amlodipine 5mg 服藥時間到', False),
    ('medication_confirmed', '服藥確認',     'Rita 已記錄 08:00 早藥服用',         True),
    ('leave_request',        '請假申請',     'Rita Santos 申請事假，請審核',       False),
    ('leave_status',         '請假已通過',   '你的私人假已通過',                   True),
    ('board_request',        '採購需求',     'Rita 提出新的採購需求：成人紙尿褲',   False),
    ('chat_message',         '新訊息',       'Rita: 爺爺今天吃得不錯',            True),
    ('todo_assigned',        '待辦指派',     '你被指派了「補購復健護具」',         False),
    ('event_reminder',       '行程提醒',     '心臟科回診：明天 09:00 台大醫院',     False),
    ('sos',                  '🆘 緊急求助', '王爺爺觸發了 SOS 緊急求助',          True),
]
for ntype, title, body, is_read in notifications:
    Notification.objects.create(
        user=hank, type=ntype,
        title=title, body=body,
        data={},
        is_read=is_read,
    )

# 推播裝置（測試 token，不會真的送到 APNs）
Device.objects.create(
    user=hank,
    device_token='fake-apns-token-for-testing-hank',
    platform='ios',
    device_name='Hank 的 iPhone',
    is_active=True,
)
Device.objects.create(
    user=rita,
    device_token='fake-apns-token-for-testing-rita',
    platform='ios',
    device_name='Rita 的 iPhone',
    is_active=True,
)

print(f'   ✓ Notification: {Notification.objects.count()}, Device: {Device.objects.count()}')


# ============================================================================
# Summary
# ============================================================================
print()
print('=' * 60)
print('🎉  所有資料表已重新填充完成！')
print('=' * 60)
print()
print('📋 摘要：')
print(f'   • User: {User.objects.count()}')
print(f'   • Family: {Family.objects.count()}')
print(f'   • Chat / Message: {Chat.objects.count()} / {Message.objects.count()}')
print(f'   • BoardRequest: {BoardRequest.objects.count()}')
print(f'   • CareLog: {CareLog.objects.count()}')
print(f'   • Medication / Confirmation: {Medication.objects.count()} / {MedicationConfirmation.objects.count()}')
print(f'   • Expense: {Expense.objects.count()}')
print(f'   • Leave / Vote: {Leave.objects.count()} / {LeaveVote.objects.count()}')
print(f'   • HealthData / Alert: {HealthData.objects.count()} / {HealthAlert.objects.count()}')
print(f'   • Event: {Event.objects.count()}')
print(f'   • Todo: {Todo.objects.count()}')
print(f'   • Document: {Document.objects.count()}')
print(f'   • AIConversation / FirstAidDocument: {AIConversation.objects.count()} / {FirstAidDocument.objects.count()}')
print(f'   • SOSRecord: {SOSRecord.objects.count()}')
print(f'   • Notification / Device: {Notification.objects.count()} / {Device.objects.count()}')
print()
print('🔐 登入資訊：所有帳號密碼皆為 test1234')
print('   主測試家屬：hank@carebridge.com')
print('   王家邀請碼：202600')
