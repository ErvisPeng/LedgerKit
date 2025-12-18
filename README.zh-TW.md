# LedgerKit

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2012+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/ErvisPeng/LedgerKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ErvisPeng/LedgerKit/actions/workflows/ci.yml)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-贊助作者-orange?style=flat&logo=buy-me-a-coffee)](https://buymeacoffee.com/ervispeng)

[English](README.md) | 繁體中文

一個用於解析各券商交易資料的 Swift 函式庫，將不同格式統一轉換為標準格式。

## 功能特色

- **多券商支援** - 解析 Charles Schwab (JSON) 和 Firstrade (CSV) 的交易紀錄
- **統一輸出格式** - 所有券商輸出相同的 `ParsedTrade` 格式，方便整合
- **選擇權支援** - 完整支援選擇權交易，包括買賣權、履約、到期等
- **型別安全** - 強型別的交易類型與錯誤處理
- **零依賴** - 僅依賴 Foundation，無外部套件依賴
- **執行緒安全** - 完整支援 Swift Concurrency，符合 `Sendable` 協定

## 支援的券商

| 券商 | 格式 | 狀態 | 說明 |
|------|------|------|------|
| Charles Schwab | JSON | ✅ 已支援 | 從 Schwab 網站匯出 |
| Firstrade | CSV | ✅ 已支援 | 從 Firstrade 網站匯出 |

## 安裝

### Swift Package Manager

透過 Xcode 加入 LedgerKit：

1. **File** > **Add Package Dependencies**
2. 輸入 repository URL：
   ```
   https://github.com/ErvisPeng/LedgerKit.git
   ```
3. 選擇版本：`0.1.0` 或更新版本

或在 `Package.swift` 中加入：

```swift
dependencies: [
    .package(url: "https://github.com/ErvisPeng/LedgerKit.git", from: "0.1.0")
]
```

然後在 target 的 dependencies 中加入 `LedgerKit`：

```swift
.target(
    name: "YourApp",
    dependencies: ["LedgerKit"]
)
```

## 快速開始

### 解析 Charles Schwab JSON

```swift
import LedgerKit

// 載入匯出的 JSON 檔案
let jsonData = try Data(contentsOf: schwabExportURL)

// 解析交易紀錄
let parser = CharlesSchwabParser()
let trades = try parser.parse(jsonData)

// 使用解析後的交易資料
for trade in trades {
    print("\(trade.tradeDate): \(trade.type) \(trade.quantity) \(trade.ticker)")
}
```

### 解析 Firstrade CSV

```swift
import LedgerKit

// 載入匯出的 CSV 檔案
let csvData = try Data(contentsOf: firstradeExportURL)

// 解析交易紀錄
let parser = FirstradeParser()
let trades = try parser.parse(csvData)
```

### 取得警告訊息

部分交易可能產生警告（例如：無法識別的交易類型）。使用 `parseWithWarnings` 來取得警告：

```swift
let parser = CharlesSchwabParser()
let (trades, warnings) = try parser.parseWithWarnings(jsonData)

for warning in warnings {
    print("警告: \(warning)")
}
```

## 輸出格式

所有解析器輸出統一的 `ParsedTrade` 結構：

```swift
public struct ParsedTrade: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let type: ParsedTradeType
    public let ticker: String
    public let quantity: Double
    public let price: Double
    public let totalAmount: Double
    public let tradeDate: Date
    public let optionInfo: ParsedOptionInfo?
    public let note: String
    public let rawSource: String
}
```

### 交易類型

```swift
public enum ParsedTradeType: String, Sendable {
    // 股票交易
    case stockBuy           // 買入股票
    case stockSell          // 賣出股票

    // 選擇權交易
    case optionBuy          // 買入選擇權
    case optionSell         // 賣出選擇權
    case optionBuyToOpen    // 買入開倉
    case optionBuyToClose   // 買入平倉
    case optionSellToOpen   // 賣出開倉
    case optionSellToClose  // 賣出平倉
    case optionExpiration   // 選擇權到期
    case optionAssignment   // 選擇權履約

    // 收入
    case dividend           // 股息
    case dividendReinvest   // 股息再投資

    // 公司行動
    case symbolExchangeIn   // 換股轉入
    case symbolExchangeOut  // 換股轉出
}
```

### 選擇權資訊

選擇權交易的 `ParsedTrade.optionInfo` 包含：

```swift
public struct ParsedOptionInfo: Sendable, Equatable {
    public let underlyingTicker: String  // 標的代號，如 "AAPL"
    public let optionType: OptionType    // .call 或 .put
    public let strikePrice: Double       // 履約價，如 150.0
    public let expirationDate: Date      // 到期日
}
```

## 錯誤處理

每個解析器有專屬的錯誤類型：

```swift
do {
    let trades = try parser.parse(data)
} catch let error as CharlesSchwabParserError {
    switch error {
    case .invalidJSON:
        print("無效的 JSON 格式")
    case .missingRequiredField(let field):
        print("缺少必要欄位: \(field)")
    case .invalidDateFormat(let dateString):
        print("無效的日期格式: \(dateString)")
    }
} catch let error as FirstradeParserError {
    switch error {
    case .invalidCSVFormat:
        print("無效的 CSV 格式")
    case .missingHeader:
        print("找不到 CSV 標頭")
    case .invalidDateFormat(let dateString):
        print("無效的日期格式: \(dateString)")
    }
}
```

## 如何匯出交易紀錄

### Charles Schwab

1. 登入 [schwab.com](https://www.schwab.com)
2. 前往 **Accounts** > **History**
3. 選擇日期範圍並點擊 **Export**
4. 選擇 **JSON** 格式

### Firstrade

1. 登入 [firstrade.com](https://www.firstrade.com)
2. 前往 **Accounts** > **History**
3. 選擇日期範圍並點擊 **Download**
4. 選擇 **CSV** 格式

## 新增券商支援

想要新增其他券商的支援？LedgerKit 設計為易於擴展。

1. 建立新的解析器類別，實作 `BrokerParser` 協定
2. 如需要，建立券商專屬的資料類型
3. 撰寫單元測試與範例資料
4. 提交 Pull Request

詳細說明請參閱 [CONTRIBUTING.zh-TW.md](CONTRIBUTING.zh-TW.md)。

## 系統需求

- Swift 5.9+
- iOS 15+ / macOS 12+

## 授權

LedgerKit 使用 MIT 授權。詳情請參閱 [LICENSE](LICENSE) 檔案。

## 貢獻

歡迎貢獻！提交 Pull Request 前請先閱讀 [CONTRIBUTING.zh-TW.md](CONTRIBUTING.zh-TW.md)。

## 致謝

- 源於對統一匯入各券商資料到個人理財 App 的需求
- 採用 Swift 最佳實踐與現代並行支援建構
