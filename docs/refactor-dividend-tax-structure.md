# 重構計劃：股息稅金結構 + Decimal 精度

## 一、問題概述

### 1.1 當前問題

1. **配息與稅金分離**：`NRA Tax Adj` 被完全跳過，無法記錄實際淨收入
2. **缺少關聯機制**：`ItemIssueId` 存在但未被使用來關聯相關交易
3. **浮點精度問題**：使用 `Double` 可能導致金額計算誤差
4. **結構不夠靈活**：所有交易共用同一個 struct，但不同類型需要的欄位差異很大

### 1.2 範例資料

```json
{
  "Date": "06/28/2024",
  "Action": "NRA Tax Adj",
  "Symbol": "NVDA",
  "Description": "NVIDIA CORP",
  "Amount": "-$0.81",
  "ItemIssueId": "382397811"
},
{
  "Date": "06/28/2024",
  "Action": "Qualified Dividend",
  "Symbol": "NVDA",
  "Description": "NVIDIA CORP",
  "Amount": "$2.70",
  "ItemIssueId": "382397811"
}
```

這兩筆記錄有相同的 `ItemIssueId`，應該合併為一筆股息記錄。

### 1.3 目標

- 配息記錄包含預扣稅金資訊（淨額 = 股息 - 稅金）
- 使用 `Decimal` 確保金額精確
- 使用 enum + associated values 讓不同交易類型有明確的資料結構

---

## 二、新資料結構設計

### 2.1 新增 `DividendInfo` 結構

```swift
/// 股息資訊（含稅金）
public struct DividendInfo: Sendable, Equatable, Hashable, Codable {
    /// 股息類型
    public enum DividendType: String, Sendable, Codable {
        case qualified = "qualified"        // Qualified Dividend
        case ordinary = "ordinary"          // Cash Dividend
        case capitalGain = "capital_gain"   // Long Term Cap Gain
        case reinvest = "reinvest"          // Dividend Reinvest
    }

    public let type: DividendType
    public let grossAmount: Decimal      // 稅前股息
    public let taxWithheld: Decimal      // 預扣稅金（正數）
    public let issueId: String?          // 用於關聯的 ItemIssueId

    /// 實際收到的淨額
    public var netAmount: Decimal {
        grossAmount - taxWithheld
    }
}
```

### 2.2 修改 `ParsedTrade`

```swift
public struct ParsedTrade: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let type: ParsedTradeType
    public let ticker: String
    public let quantity: Decimal          // Double → Decimal
    public let price: Decimal             // Double → Decimal
    public let totalAmount: Decimal       // Double → Decimal
    public let tradeDate: Date
    public let optionInfo: ParsedOptionInfo?
    public let dividendInfo: DividendInfo?  // 新增：股息專用資訊
    public let note: String
    public let rawSource: String
}
```

### 2.3 修改 `ParsedOptionInfo`

```swift
public struct ParsedOptionInfo: Sendable, Equatable, Hashable, Codable {
    public let underlyingTicker: String
    public let optionType: OptionType
    public let strikePrice: Decimal       // Double → Decimal
    public let expirationDate: Date
}
```

### 2.4 修改 `FirstradeCSVRecord`

```swift
public struct FirstradeCSVRecord: Sendable, Equatable {
    // ...
    public let quantity: Decimal          // Double → Decimal
    public let price: Decimal             // Double → Decimal
    public let interest: Decimal          // Double → Decimal
    public let amount: Decimal            // Double → Decimal
    public let commission: Decimal        // Double → Decimal
    public let fee: Decimal               // Double → Decimal
}
```

---

## 三、解析邏輯修改

### 3.1 Charles Schwab Parser

**新增：按 ItemIssueId 分組處理**

```swift
func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
    let records = try decodeRecords(data)

    // 1. 先按 ItemIssueId 分組
    let grouped = Dictionary(grouping: records) { $0.itemIssueId }

    var trades: [ParsedTrade] = []

    for (issueId, group) in grouped {
        if issueId.isEmpty {
            // 沒有 issueId 的記錄，單獨處理
            trades.append(contentsOf: group.compactMap { parseRecord($0) })
        } else {
            // 有 issueId 的記錄，嘗試合併 dividend + tax
            if let merged = tryMergeDividendWithTax(group, issueId: issueId) {
                trades.append(merged)
            } else {
                trades.append(contentsOf: group.compactMap { parseRecord($0) })
            }
        }
    }

    return (trades, warnings)
}

private func tryMergeDividendWithTax(
    _ records: [CharlesSchwabRawTransaction],
    issueId: String
) -> ParsedTrade? {
    let dividendRecord = records.first {
        CharlesSchwabActionType(rawAction: $0.action)?.isDividend == true
    }
    let taxRecord = records.first { $0.action == "NRA Tax Adj" }

    guard let dividend = dividendRecord else { return nil }

    let grossAmount = parseAmount(dividend.amount)
    let taxAmount = taxRecord.map { abs(parseAmount($0.amount)) } ?? .zero

    let dividendInfo = DividendInfo(
        type: mapDividendType(dividend.action),
        grossAmount: grossAmount,
        taxWithheld: taxAmount,
        issueId: issueId
    )

    return ParsedTrade(
        type: .dividend,
        ticker: dividend.symbol,
        quantity: .zero,
        price: .zero,
        totalAmount: dividendInfo.netAmount,  // 使用淨額
        tradeDate: parseDate(dividend.date),
        dividendInfo: dividendInfo,
        note: "...",
        rawSource: "Charles Schwab"
    )
}
```

### 3.2 金額解析改用 Decimal

```swift
// 舊
private func parseAmount(_ string: String) -> Double {
    return Double(cleaned) ?? 0
}

// 新
private func parseAmount(_ string: String) -> Decimal {
    return Decimal(string: cleaned) ?? .zero
}
```

---

## 四、影響範圍

### 4.1 需要修改的檔案

| 檔案 | 修改內容 |
|------|----------|
| `Models/ParsedTrade.swift` | Double → Decimal, 新增 dividendInfo |
| `Models/ParsedOptionInfo.swift` | strikePrice: Double → Decimal |
| `Models/DividendInfo.swift` | **新建**：股息資訊結構 |
| `Parsers/CharlesSchwab/CharlesSchwabParser.swift` | Decimal 解析 + 分組合併邏輯 |
| `Parsers/CharlesSchwab/CharlesSchwabActionType.swift` | 加入 `nraTaxAdj` 到處理流程 |
| `Parsers/Firstrade/FirstradeParser.swift` | Decimal 解析 |
| `Parsers/Firstrade/FirstradeCSVRecord.swift` | Double → Decimal |
| `Tests/CharlesSchwabParserTests.swift` | 更新測試 + 新增合併測試 |
| `Tests/FirstradeParserTests.swift` | 更新測試 |

### 4.2 公開 API 變更（Breaking Changes）

1. `ParsedTrade.quantity/price/totalAmount` 從 `Double` 改為 `Decimal`
2. `ParsedTrade` 新增 `dividendInfo: DividendInfo?` 欄位
3. `ParsedOptionInfo.strikePrice` 從 `Double` 改為 `Decimal`

---

## 五、實作步驟

### Phase 1：基礎結構變更

1. 新建 `DividendInfo.swift`
2. 修改 `ParsedTrade.swift`（加入 dividendInfo，Double → Decimal）
3. 修改 `ParsedOptionInfo.swift`（Double → Decimal）
4. 修改 `FirstradeCSVRecord.swift`（Double → Decimal）

### Phase 2：解析器更新

5. 修改 `CharlesSchwabParser.swift`（Decimal + 分組合併）
6. 修改 `CharlesSchwabActionType.swift`（調整 shouldImport）
7. 修改 `FirstradeParser.swift`（Decimal）

### Phase 3：測試更新

8. 更新 `CharlesSchwabParserTests.swift`
9. 更新 `FirstradeParserTests.swift`
10. 新增股息+稅金合併的測試案例

---

## 六、測試案例

### 6.1 股息+稅金合併測試

```swift
@Test("Dividend with NRA Tax Adj merged correctly")
func dividendWithTaxMerged() throws {
    let transactions = [
        makeTransaction(
            action: "Qualified Dividend",
            symbol: "NVDA",
            amount: "$2.70",
            itemIssueId: "382397811"
        ),
        makeTransaction(
            action: "NRA Tax Adj",
            symbol: "NVDA",
            amount: "-$0.81",
            itemIssueId: "382397811"
        )
    ]

    let trades = try parser.parse(makeJSONData(transactions: transactions))

    #expect(trades.count == 1)
    #expect(trades[0].type == .dividend)
    #expect(trades[0].totalAmount == Decimal(string: "1.89"))  // 2.70 - 0.81
    #expect(trades[0].dividendInfo?.grossAmount == Decimal(string: "2.70"))
    #expect(trades[0].dividendInfo?.taxWithheld == Decimal(string: "0.81"))
}
```

### 6.2 純股息（無稅金）測試

```swift
@Test("Dividend without tax works correctly")
func dividendWithoutTax() throws {
    let transactions = [
        makeTransaction(
            action: "Qualified Dividend",
            symbol: "AAPL",
            amount: "$5.00",
            itemIssueId: "123456"
        )
    ]

    let trades = try parser.parse(makeJSONData(transactions: transactions))

    #expect(trades.count == 1)
    #expect(trades[0].totalAmount == Decimal(string: "5.00"))
    #expect(trades[0].dividendInfo?.grossAmount == Decimal(string: "5.00"))
    #expect(trades[0].dividendInfo?.taxWithheld == .zero)
}
```

### 6.3 Decimal 精度測試

```swift
@Test("Decimal precision maintained")
func decimalPrecision() throws {
    // 驗證 0.1 + 0.2 == 0.3
    let a = Decimal(string: "0.1")!
    let b = Decimal(string: "0.2")!
    #expect(a + b == Decimal(string: "0.3")!)
}
```

---

## 七、待確認問題

1. **ADR Mgmt Fee 是否也要合併？**
   - 目前也被跳過，是否要類似處理？
   - 建議：可以加入 `DividendInfo` 的 `fees` 欄位

2. **Firstrade 是否有類似的稅金記錄？**
   - 需要確認 Firstrade 的資料格式
   - 如果有，需要同步更新 FirstradeParser

3. **是否需要向後相容？**
   - 如果有序列化的資料，Decimal 的 Codable 格式可能不同
   - 建議：這是 library，使用者應該重新解析原始資料

---

## 八、預期結果

重構完成後：

```swift
let trade = trades[0]

// 股息資訊完整
print(trade.dividendInfo?.grossAmount)   // 2.70
print(trade.dividendInfo?.taxWithheld)   // 0.81
print(trade.dividendInfo?.netAmount)     // 1.89
print(trade.totalAmount)                  // 1.89 (淨額)

// 金額精確
let a = Decimal(string: "0.1")! + Decimal(string: "0.2")!
print(a == Decimal(string: "0.3")!)      // true ✅
```
