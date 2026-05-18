# CareBridge Frontend Translation Handoff

## Backend status

Backend dynamic translation is currently available for these user-entered text flows:

- Todo title: `title_translated`
- Calendar event title/note: `title_translated`, `note_translated`
- Care log content fields: `content_translated`
- Medication name/instructions/confirmation note: `name_translated`, `instructions_translated`, `note_translated`
- Leave reason/reply: `reason_translations`, `reply_translations`
- Board request item names/note/reply: `items[].name_translated`, `note_translations`, `reply_translations`
- Chat message content: `translations`
- Notification title/body: `title_translated`, `body_translated`

Translation payloads are language maps keyed by backend language code:

```json
{
  "zh-TW": "原文或中文翻譯",
  "id": "Bahasa Indonesia",
  "vi": "Tiếng Việt",
  "tl": "Tagalog"
}
```

Protected entities are intentionally not translated. Display them as-is:

- Names: user names, elder names, family names
- Contact fields: phone, email
- Medical entities: medication names, dosage, units, medication/device codes
- Places and brands: store names, hospital/clinic/pharmacy names, addresses
- Document numbers and time values

Receipt OCR raw text and document raw content are not sent to GPT and should not be machine-translated in the UI.

## iOS issues to fix

### Static UI labels

Several SwiftUI views still pass runtime `String` values into `Text`, so SwiftUI does not always resolve `Localizable.xcstrings`.

Examples:

- `ProfileView.profileRow(icon:label:value:)` renders labels like `姓名`, `電話`, `電子郵件`, `家庭名稱` with `Text(label)`.
- Form labels in profile, todo, calendar, spending, care log, leave, board, medication, notification settings need consistent localization.

Frontend fix:

- Use `LocalizedStringKey` for static labels, or call `String(localized:)` at the point where a localized `String` is required.
- Do not translate the displayed values for `name`, `phone`, `email`, or `familyName`.
- Ensure `Localizable.xcstrings` has complete `zh-Hant`, `vi`, `id`, and `tl` entries.
- Add the corresponding known regions to the Xcode project if missing.

### Date and time display

Some screens force Chinese date formatting.

Known examples:

- `SharedCalendarView.monthFormatter` sets `Locale(identifier: "zh-TW")`.
- `CareLogView` uses `Locale(identifier: "zh-TW")` for calendar/date strings.
- `LeaveRequestDetailView` uses `yyyy/M/d（E）` with `zh-TW`.
- Several views call `DateFormatter()` directly without applying the app language.

Frontend fix:

- Create a shared date formatting helper that accepts `LocaleStore.locale`.
- Replace fixed `zh-TW` formatters with locale-aware formatters.
- For Swift `Date.FormatStyle`, explicitly apply `.locale(localeStore.locale)` where environment locale is not respected.
- Keep API wire dates in stable formats such as `yyyy-MM-dd` with `en_US_POSIX`; only display strings should localize.

### Expense category display

Backend now normalizes expense item categories to canonical wire codes:

- `medical`
- `food`
- `daily`
- `transport`
- `other`

Frontend fix:

- Store and submit category codes, not Chinese labels.
- Render category display names through localized enum mapping.
- Replace hard-coded arrays such as `["醫療保健", "日常飲食", "生活用品", "交通", "其他"]` with code-backed options.
- In spending summaries, treat `categoryBreakdown[].category` as a wire code and localize only for display.

Suggested display mapping:

| Code | zh-TW | vi | id | tl |
| --- | --- | --- | --- | --- |
| `medical` | 醫療保健 | Y tế | Kesehatan | Medikal |
| `food` | 日常飲食 | Ăn uống | Makanan | Pagkain |
| `daily` | 生活用品 | Đồ dùng hằng ngày | Kebutuhan harian | Pang-araw-araw |
| `transport` | 交通 | Di chuyển | Transportasi | Transportasyon |
| `other` | 其他 | Khác | Lainnya | Iba pa |

### Dynamic translated fields

Use the current user language to pick a translated value, then fallback to the original field.

Recommended helper:

```swift
func translatedText(
    original: String,
    translations: [String: String]?,
    language: String?
) -> String {
    guard let language,
          let translated = translations?[language],
          !translated.isEmpty else {
        return original
    }
    return translated
}
```

Apply this to:

- Todo: decode `title_translated` and render translated title in `TodoView` and calendar todo rows.
- Calendar: decode and render `title_translated` and `note_translated`.
- Care log: decode `content_translated`; build title/detail from translated content fields for the active language.
- Medication: keep medication names unchanged, but decode/render `instructions_translated` and confirmation `note_translated`.
- Leave: render `reason_translations` and `reply_translations`.
- Board: render `items[].name_translated`, `note_translations`, and `reply_translations`.
- Notification center: render `title_translated` and `body_translated`.
- Chat already has a translation helper, but verify it uses the same language fallback behavior.

### Todo example

Current issue:

1. Family member creates a todo in Chinese.
2. User switches app language to Vietnamese.
3. `TodoItem` still displays `title`, because iOS does not decode `title_translated`.

Expected behavior:

1. Backend response includes `title_translated`.
2. `TodoItem` stores `titleTranslations: [String: String]?`.
3. Todo rows call `todo.displayTitle(language: userStore.currentUser?.language ?? localeStore.code)`.
4. If no translation exists, show `title`.

## Acceptance criteria

- Switching to Vietnamese, Indonesian, or Tagalog changes static labels throughout the app.
- Profile labels localize, but actual profile values remain original.
- All date/time labels render in the selected app language.
- Expense category labels localize while API payloads remain canonical category codes.
- Newly created todo/calendar/care-log/leave/board/notification records display translated dynamic text after the API returns translated fields.
- Medical and protected entities remain unchanged across languages.
