import Foundation

/// 從 `*_translated` 翻譯字典挑出當前語言的版本。空字串或缺鍵都回原文，
/// 確保 UI 永遠有東西可顯示。語言 code 對齊後端 `core.translation.SUPPORTED_LANGUAGES`
/// （zh-TW / id / vi / tl）。
func translatedText(original: String, translations: [String: String]?, language: String?) -> String {
    guard let language,
          let translated = translations?[language],
          !translated.isEmpty else {
        return original
    }
    return translated
}

/// 集中管理會被「App 語言」影響的 formatter。各 view 之前各自 new 一個
/// DateFormatter 又硬寫 `Locale(identifier: "zh-TW")`，切語言時不會更新；
/// 改成從這裡拿 + 傳入 `LocaleStore.locale`，整個 app 才會跟著切。
///
/// 注意：API 線上格式（`yyyy-MM-dd` 之類）一律走 `wireDate*`，固定
/// `en_US_POSIX`，不能跟顯示用 formatter 混。
enum LocalizedFormatters {

    /// 「2026 年 5 月」這種月份標題 —— 依當前 locale 選樣式。
    static func monthYear(for locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f
    }

    /// 「2026/5/12（一）」這種附星期幾的短日期；多用於請假明細之類。
    static func shortDateWithWeekday(for locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMdEEE")
        return f
    }

    /// 「5/12」這種僅月日 —— 列表簡稱。
    static func monthDay(for locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }

    // MARK: - Wire (API) formatters
    /// 後端 `yyyy-MM-dd` 上行/下行用，固定 POSIX locale，永遠不可本地化。
    static let wireDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
