# 貢獻指南

感謝您有興趣為 LedgerKit 做出貢獻！本文件提供貢獻的指南與說明。

## 行為準則

請閱讀並遵守我們的[行為準則](CODE_OF_CONDUCT.zh-TW.md)。

## 如何貢獻

### 回報 Bug

如果您發現 bug，請建立 issue 並包含：

1. 清楚、描述性的標題
2. 重現問題的步驟
3. 預期行為與實際行為的差異
4. 導致問題的範例資料（需去識別化）
5. 您的環境（Swift 版本、平台等）

**重要**：分享範例資料時，請移除或匿名化任何個人或財務資訊。

### 功能建議

歡迎功能請求！請建立 issue 並包含：

1. 功能的清楚描述
2. 功能的使用情境
3. 任何相關的範例或示意圖

### 新增券商支援

我們歡迎新增其他券商支援的貢獻！步驟如下：

#### 1. 建立 Parser 目錄

```
Sources/LedgerKit/Parsers/YourBroker/
├── YourBrokerParser.swift
├── YourBrokerRawRecord.swift  (如需要)
└── YourBrokerActionType.swift (如需要)
```

#### 2. 實作 BrokerParser 協定

```swift
import Foundation

public final class YourBrokerParser: BrokerParser, Sendable {

    public static let brokerName = "Your Broker"
    public static let supportedFormats: [FileFormat] = [.csv]  // 或 [.json]

    public init() {}

    public func parse(_ data: Data) throws -> [ParsedTrade] {
        let (trades, _) = try parseWithWarnings(data)
        return trades
    }

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        // 您的解析邏輯
        var trades: [ParsedTrade] = []
        var warnings: [String] = []

        // 解析資料...

        return (trades, warnings)
    }
}
```

#### 3. 建立錯誤類型

```swift
// Sources/LedgerKit/Errors/YourBrokerError.swift

public enum YourBrokerParserError: Error, Sendable {
    case invalidFormat
    case missingRequiredField(String)
    case invalidDateFormat(String)
    // 新增券商專屬錯誤
}
```

#### 4. 撰寫單元測試

在 `Tests/LedgerKitTests/YourBroker/` 建立完整測試：

```swift
import Testing
@testable import LedgerKit

struct YourBrokerParserTests {

    let parser = YourBrokerParser()

    @Test func parseStockBuy() throws {
        let data = """
        // 您的範例資料
        """.data(using: .utf8)!

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .stockBuy)
        #expect(trades[0].ticker == "AAPL")
    }

    // 新增更多測試...
}
```

#### 5. 更新 SupportedBroker 列舉

在 `Sources/LedgerKit/Core/SupportedBroker.swift` 中加入您的券商：

```swift
public enum SupportedBroker: String, CaseIterable, Sendable {
    case charlesSchwab = "Charles Schwab"
    case firstrade = "Firstrade"
    case yourBroker = "Your Broker"  // 新增這行
}
```

#### 6. 更新文件

- 在 README.md 的支援券商表格中加入您的券商
- 包含您的券商的匯出說明
- 更新 CHANGELOG.md

### Pull Request 流程

1. **Fork repository** 並從 `main` 建立您的分支
2. **撰寫測試** 涵蓋新功能
3. **確保所有測試通過**：`swift test`
4. **遵循專案的程式碼風格**
5. **視需要更新文件**
6. **建立 Pull Request** 並提供清楚的描述

### 程式碼規範

#### Swift 風格

- 使用 Swift 5.9+ 功能
- 遵循 [Swift API 設計指南](https://swift.org/documentation/api-design-guidelines/)
- 使用有意義的變數和函式名稱
- 為公開 API 加入文件註解

#### 程式碼品質

- 所有公開類型必須符合 `Sendable` 以確保並行安全
- 僅對要供外部使用的類型使用 `public` 存取層級
- 使用描述性的錯誤類型優雅地處理錯誤
- 避免強制解包（`!`）- 使用 `guard` 或 `if let`

#### 測試

- 為所有新功能撰寫測試
- 使用 Swift Testing 框架（`import Testing`）
- 包含邊界案例和錯誤情境
- 使用實際的範例資料（需去識別化）

### 開發環境設定

1. Clone repository：
   ```bash
   git clone https://github.com/ErvisPeng/LedgerKit.git
   cd LedgerKit
   ```

2. 建置專案：
   ```bash
   swift build
   ```

3. 執行測試：
   ```bash
   swift test
   ```

### Commit 訊息

使用清楚、描述性的 commit 訊息：

- `feat: 新增 YourBroker CSV 解析器`
- `fix: 修正 Firstrade 解析器空數量處理`
- `docs: 更新 README 新增券商說明`
- `test: 新增選擇權解析邊界案例測試`
- `refactor: 抽取共用日期解析邏輯`

## 有問題嗎？

如果您有問題，歡迎：

1. 開啟 issue 進行討論
2. 查看現有的 issues 和 pull requests

感謝您的貢獻！
