# CareBridge 照護橋

**CareBridge** 是一款專為外籍看護、長者及其家屬設計的智慧照護管理 APP，旨在透過科技打破語言與距離的障礙，讓照護溝通更順暢、健康管理更即時、日常事務更透明。

本專案為參加 **2026 MAIC 行動應用創意競賽** 之作品。

## 核心特色

- **即時翻譯聊天** — 看護與家屬跨語言無障礙溝通
- **健康監測儀表板** — 整合 Apple Watch / HealthKit，即時追蹤長者心率、血氧、血壓、血糖等生理數據
- **照護日誌** — 每日照護紀錄，含用餐、用藥、活動、情緒等項目
- **用藥管理** — 藥物排程與提醒，避免漏服
- **消費記帳** — 照護相關支出透明記錄
- **AI 智慧助理** — 照護建議、健康分析、多語翻譯
- **SOS 緊急呼叫** — 一鍵求助，自動發送定位與健康數據
- **Apple Watch 支援** — 長者端獨立運作，跌倒偵測與 SOS

## 技術棧

| 類別 | 技術 |
|---|---|
| 平台 | iOS 26 / watchOS 26 |
| 語言 | Swift |
| UI 框架 | SwiftUI |
| 圖表 | Swift Charts |
| 健康數據 | HealthKit |
| 後端 API | RESTful JSON（JWT 認證） |

## 使用者角色

| 角色 | 說明 |
|---|---|
| 看護 | 外籍看護，負責日常照護紀錄與溝通 |
| 家屬 | 長者家屬，遠端關心與管理 |
| 長者 | 被照護者，主要透過 Apple Watch 互動 |

## 資料夾結構

```
CareBridge/
├── .gitignore
├── README.md
├── CareBridge_API_Documentation.md  # 後端 API 規格文件
├── CareBridge_Feature_List.md       # 系統功能清單（90 項功能）
├── CareBridge_提案書.pdf              # 競賽提案書
│
├── CareBridge/                      # 主要 App 原始碼
│   ├── CareBridgeApp.swift          # App 進入點
│   ├── ContentView.swift            # 主畫面（TabView）
│   ├── AppModels.swift              # 資料模型定義
│   ├── HomeView.swift               # 首頁（健康摘要、SOS）
│   ├── ChatListView.swift           # 聊天列表
│   ├── CareLogView.swift            # 照護日誌
│   ├── SpendingView.swift           # 消費記帳
│   ├── MoreView.swift               # 更多功能入口
│   ├── HealthMonitorView.swift      # 健康監測儀表板
│   ├── MedicationView.swift         # 用藥管理
│   ├── SharedCalendarView.swift     # 共享行事曆
│   ├── TodoView.swift               # 代辦事項
│   ├── LeaveManagementView.swift    # 請假管理
│   ├── MessageBoardView.swift       # 留言板
│   ├── DocumentsView.swift          # 文件管理
│   ├── NotificationCenterView.swift # 通知中心
│   ├── AIAgentView.swift            # AI 智慧助理
│   ├── FirstAidView.swift           # AI 急救小幫手
│   ├── SOSView.swift                # SOS 緊急呼叫
│   └── Assets.xcassets/             # 圖片與顏色資源
│
├── CareBridge.xcodeproj/            # Xcode 專案設定
├── CareBridgeTests/                 # 單元測試
└── CareBridgeUITests/               # UI 測試
```

## 開發環境

- **Xcode 26+**
- **macOS Tahoe 26+**
- **iOS 26 Simulator 或實機**

## 團隊

MAIC 2026 參賽團隊

## 授權

本專案為競賽作品，未經授權請勿轉載或使用。
