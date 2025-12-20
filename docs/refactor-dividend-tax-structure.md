# 重構計劃：股息稅金結構 + Decimal 精度

## 一、問題概述

### 1.1 當前問題

1. **配息與稅金分離**：`NRA Tax Adj` 被完全跳過，無法記錄實際淨收入
2. **缺少關聯機制**：`ItemIssueId` 存在但未被使用來關聯相關交易
3. **浮點精度問題**：使用 `Double` 可能導致金額計算誤差
4. **結構不夠靈活**：所有交易共用同一個 struct，但不同類型需要的欄位差異很大

### 1.2 範例資料

**股息 + 稅金（同一 ItemIssueId）：**
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

**ADR 管理費（獨立記錄）：**
```json
{
  "Date": "10/11/2022",
  "Action": "ADR Mgmt Fee",
  "Symbol": "",
  "Description": "TDA TRAN - ADR FEE (SE)",
  "Amount": "-$0.08",
  "ItemIssueId": "0"
}
```

Symbol 為空，但可從 Description 解析出股票代號 `SE`。應作為獨立的 `fee` 類型記錄。

**Firstrade ADR 管理費：**
```csv
ARM,0.00,,Other,***ARM HOLDINGS PLC AMERICAN DEPOSITARY SHARES ADR Fee 2023-12-18 Qty - 10.0000000000 0953- CITIBANK,2024-01-12,2024-01-12,0.00,-0.2,0.00,0.00,042068205,Financial
```

- Symbol 欄位有值 `ARM`
- Action = `Other`，RecordType = `Financial`
- Description 包含 `ADR Fee` 關鍵字

**Firstrade 股息（含預扣稅）：**
```csv
KO,0.00,,Dividend,COCA COLA COMPANY (THE) CASH DIV ON 10.31822 SHS REC 06/13/25 PAY 07/01/25 NON-RES TAX WITHHELD $1.58,2025-07-01,2025-07-01,0.00,5.26,0.00,0.00,191216100,Financial
```

- Action = `Dividend`，RecordType = `Financial`
- Amount = `5.26` 是**淨額**（已扣稅）
- Description 包含 `NON-RES TAX WITHHELD $1.58`
- 毛額需計算：淨額 + 稅金 = $5.26 + $1.58 = $6.84

### 1.3 目標

- 配息記錄包含預扣稅金資訊（淨額 = 股息 - 稅金）
- ADR 管理費作為獨立的 `fee` 類型記錄
- 使用 `Decimal` 確保金額精確

---

## 二、新資料結構設計

### 2.1 修改 `ParsedTradeType`

```swift
public enum ParsedTradeType: String, Sendable, CaseIterable, Codable {
    // ... 現有 cases

    // 新增
    case fee = "fee"  // ADR 管理費等費用
}
```

### 2.2 新增 `DividendInfo` 結構

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

### 2.3 新增 `FeeInfo` 結構

```swift
/// 費用資訊
public struct FeeInfo: Sendable, Equatable, Hashable, Codable {
    /// 費用類型
    public enum FeeType: String, Sendable, Codable {
        case adrMgmtFee = "adr_mgmt_fee"  // ADR 管理費
    }

    public let type: FeeType
    public let amount: Decimal  // 費用金額（正數）
}
```

### 2.4 修改 `ParsedTrade`

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
    public let feeInfo: FeeInfo?            // 新增：費用專用資訊
    public let note: String
    public let rawSource: String
}
```

### 2.5 修改 `ParsedOptionInfo`

```swift
public struct ParsedOptionInfo: Sendable, Equatable, Hashable, Codable {
    public let underlyingTicker: String
    public let optionType: OptionType
    public let strikePrice: Decimal       // Double → Decimal
    public let expirationDate: Date
}
```

### 2.6 修改 `FirstradeCSVRecord`

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

### 3.2 ADR Mgmt Fee 解析

```swift
private func parseADRFee(_ record: CharlesSchwabRawTransaction) -> ParsedTrade? {
    guard record.action == "ADR Mgmt Fee" else { return nil }

    // 從 Description 解析股票代號，例如 "TDA TRAN - ADR FEE (SE)" → "SE"
    let symbol = parseSymbolFromDescription(record.description)
    guard let symbol = symbol, !symbol.isEmpty else { return nil }

    let amount = abs(parseAmount(record.amount))

    return ParsedTrade(
        type: .fee,
        ticker: symbol,
        quantity: .zero,
        price: .zero,
        totalAmount: amount,
        tradeDate: parseDate(record.date),
        feeInfo: FeeInfo(type: .adrMgmtFee, amount: amount),
        note: record.description,
        rawSource: "Charles Schwab"
    )
}

/// 從 Description 解析股票代號
/// 例如 "TDA TRAN - ADR FEE (SE)" → "SE"
private func parseSymbolFromDescription(_ description: String) -> String? {
    let pattern = #"\(([A-Z]+)\)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
              in: description,
              range: NSRange(description.startIndex..., in: description)
          ),
          let range = Range(match.range(at: 1), in: description) else {
        return nil
    }
    return String(description[range])
}
```

### 3.3 Firstrade ADR Fee 解析

```swift
private func parseADRFee(_ record: FirstradeCSVRecord) -> ParsedTrade? {
    // 識別條件：Action = "Other", RecordType = "Financial", Description 含 "ADR Fee"
    guard record.action.uppercased() == "OTHER",
          record.recordType == "Financial",
          record.description.uppercased().contains("ADR FEE") else {
        return nil
    }

    let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
    guard !symbol.isEmpty else { return nil }

    let amount = abs(record.amount)

    return ParsedTrade(
        type: .fee,
        ticker: symbol,
        quantity: .zero,
        price: .zero,
        totalAmount: amount,
        tradeDate: record.tradeDate,
        feeInfo: FeeInfo(type: .adrMgmtFee, amount: amount),
        note: record.description,
        rawSource: "Firstrade"
    )
}
```

### 3.4 Firstrade 股息解析（含預扣稅）

```swift
private func parseDividend(_ record: FirstradeCSVRecord) -> ParsedTrade? {
    guard record.action.uppercased() == "DIVIDEND",
          record.recordType == "Financial" else {
        return nil
    }

    let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
    guard !symbol.isEmpty else { return nil }

    let netAmount = abs(record.amount)  // Amount 是淨額

    // 從 Description 解析預扣稅金
    // 例如 "...NON-RES TAX WITHHELD $1.58" → 1.58
    let taxWithheld = parseTaxWithheld(from: record.description) ?? .zero
    let grossAmount = netAmount + taxWithheld

    let dividendInfo = DividendInfo(
        type: .ordinary,  // Firstrade 不區分 qualified/ordinary
        grossAmount: grossAmount,
        taxWithheld: taxWithheld,
        issueId: nil
    )

    return ParsedTrade(
        type: .dividend,
        ticker: symbol,
        quantity: .zero,
        price: .zero,
        totalAmount: netAmount,  // 使用淨額
        tradeDate: record.tradeDate,
        dividendInfo: dividendInfo,
        note: record.description,
        rawSource: "Firstrade"
    )
}

/// 從 Description 解析預扣稅金
/// 例如 "NON-RES TAX WITHHELD $1.58" → 1.58
private func parseTaxWithheld(from description: String) -> Decimal? {
    let pattern = #"NON-RES TAX WITHHELD\s+\$?([\d.]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(
              in: description,
              range: NSRange(description.startIndex..., in: description)
          ),
          let range = Range(match.range(at: 1), in: description) else {
        return nil
    }
    return Decimal(string: String(description[range]))
}
```

### 3.5 金額解析改用 Decimal

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
| `Models/ParsedTrade.swift` | Double → Decimal, 新增 dividendInfo, feeInfo |
| `Models/ParsedTradeType.swift` | 新增 `fee` case |
| `Models/ParsedOptionInfo.swift` | strikePrice: Double → Decimal |
| `Models/DividendInfo.swift` | **新建**：股息資訊結構 |
| `Models/FeeInfo.swift` | **新建**：費用資訊結構 |
| `Parsers/CharlesSchwab/CharlesSchwabParser.swift` | Decimal 解析 + 分組合併 + ADR Fee 解析 |
| `Parsers/CharlesSchwab/CharlesSchwabActionType.swift` | 加入 `nraTaxAdj`, `adrMgmtFee` 到處理流程 |
| `Parsers/Firstrade/FirstradeParser.swift` | Decimal 解析 |
| `Parsers/Firstrade/FirstradeCSVRecord.swift` | Double → Decimal |
| `Tests/CharlesSchwabParserTests.swift` | 更新測試 + 新增合併測試 + ADR Fee 測試 |
| `Tests/FirstradeParserTests.swift` | 更新測試 |

### 4.2 公開 API 變更（Breaking Changes）

1. `ParsedTrade.quantity/price/totalAmount` 從 `Double` 改為 `Decimal`
2. `ParsedTrade` 新增 `dividendInfo: DividendInfo?` 欄位
3. `ParsedTrade` 新增 `feeInfo: FeeInfo?` 欄位
4. `ParsedTradeType` 新增 `fee` case
5. `ParsedOptionInfo.strikePrice` 從 `Double` 改為 `Decimal`

---

## 五、實作步驟

### Phase 1：基礎結構變更

1. 新建 `DividendInfo.swift`
2. 新建 `FeeInfo.swift`
3. 修改 `ParsedTradeType.swift`（新增 `fee` case）
4. 修改 `ParsedTrade.swift`（加入 dividendInfo, feeInfo，Double → Decimal）
5. 修改 `ParsedOptionInfo.swift`（Double → Decimal）
6. 修改 `FirstradeCSVRecord.swift`（Double → Decimal）

### Phase 2：解析器更新

7. 修改 `CharlesSchwabParser.swift`（Decimal + 分組合併 + ADR Fee 解析）
8. 修改 `CharlesSchwabActionType.swift`（調整 shouldImport）
9. 修改 `FirstradeParser.swift`（Decimal）

### Phase 3：測試更新

10. 更新 `CharlesSchwabParserTests.swift`
11. 更新 `FirstradeParserTests.swift`
12. 新增股息+稅金合併的測試案例
13. 新增 ADR Fee 解析的測試案例

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

### 6.3 Charles Schwab ADR Fee 解析測試

```swift
@Test("Charles Schwab ADR Mgmt Fee parsed correctly")
func charlesSchwabAdrMgmtFeeParsed() throws {
    let transactions = [
        makeTransaction(
            action: "ADR Mgmt Fee",
            symbol: "",
            description: "TDA TRAN - ADR FEE (SE)",
            amount: "-$0.08",
            itemIssueId: "0"
        )
    ]

    let trades = try parser.parse(makeJSONData(transactions: transactions))

    #expect(trades.count == 1)
    #expect(trades[0].type == .fee)
    #expect(trades[0].ticker == "SE")
    #expect(trades[0].totalAmount == Decimal(string: "0.08"))
    #expect(trades[0].feeInfo?.type == .adrMgmtFee)
}
```

### 6.4 Firstrade ADR Fee 解析測試

```swift
@Test("Firstrade ADR Fee parsed correctly")
func firstradeAdrFeeParsed() throws {
    let record = FirstradeCSVRecord(
        symbol: "ARM",
        quantity: 0,
        price: 0,
        action: "Other",
        description: "***ARM HOLDINGS PLC AMERICAN DEPOSITARY SHARES ADR Fee 2023-12-18",
        tradeDate: Date(),
        settledDate: Date(),
        interest: 0,
        amount: -0.2,
        commission: 0,
        fee: 0,
        cusip: "042068205",
        recordType: "Financial"
    )

    let trade = try parser.parseRecord(record)

    #expect(trade?.type == .fee)
    #expect(trade?.ticker == "ARM")
    #expect(trade?.totalAmount == Decimal(string: "0.2"))
    #expect(trade?.feeInfo?.type == .adrMgmtFee)
}
```

### 6.5 Firstrade 股息（含預扣稅）測試

```swift
@Test("Firstrade dividend with tax withheld parsed correctly")
func firstradeDividendWithTax() throws {
    let record = FirstradeCSVRecord(
        symbol: "KO",
        quantity: 0,
        price: 0,
        action: "Dividend",
        description: "COCA COLA COMPANY (THE) CASH DIV ON 10.31822 SHS REC 06/13/25 PAY 07/01/25 NON-RES TAX WITHHELD $1.58",
        tradeDate: Date(),
        settledDate: Date(),
        interest: 0,
        amount: 5.26,  // 淨額
        commission: 0,
        fee: 0,
        cusip: "191216100",
        recordType: "Financial"
    )

    let trade = try parser.parseRecord(record)

    #expect(trade?.type == .dividend)
    #expect(trade?.ticker == "KO")
    #expect(trade?.totalAmount == Decimal(string: "5.26"))        // 淨額
    #expect(trade?.dividendInfo?.grossAmount == Decimal(string: "6.84"))  // 5.26 + 1.58
    #expect(trade?.dividendInfo?.taxWithheld == Decimal(string: "1.58"))
    #expect(trade?.dividendInfo?.netAmount == Decimal(string: "5.26"))
}
```

### 6.6 Decimal 精度測試

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

## 七、向後相容策略

### 7.1 Double → Decimal 相容

保留 Double 版本的 computed properties，標記為 deprecated：

```swift
public struct ParsedTrade {
    // 新的 Decimal 屬性
    public let quantity: Decimal
    public let price: Decimal
    public let totalAmount: Decimal

    // 向後相容：deprecated Double 屬性
    @available(*, deprecated, message: "Use quantity (Decimal) instead")
    public var quantityDouble: Double {
        NSDecimalNumber(decimal: quantity).doubleValue
    }

    @available(*, deprecated, message: "Use price (Decimal) instead")
    public var priceDouble: Double {
        NSDecimalNumber(decimal: price).doubleValue
    }

    @available(*, deprecated, message: "Use totalAmount (Decimal) instead")
    public var totalAmountDouble: Double {
        NSDecimalNumber(decimal: totalAmount).doubleValue
    }
}
```

### 7.2 Codable 相容

自定義 Codable 實作，支援讀取舊格式（Double）和新格式（Decimal）：

```swift
extension ParsedTrade: Codable {
    enum CodingKeys: String, CodingKey {
        case quantity, price, totalAmount
        // ...
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 嘗試解碼為 Decimal，失敗則嘗試 Double 並轉換
        if let decimal = try? container.decode(Decimal.self, forKey: .quantity) {
            self.quantity = decimal
        } else {
            let double = try container.decode(Double.self, forKey: .quantity)
            self.quantity = Decimal(double)
        }
        // ... 其他欄位同理
    }

    public func encode(to encoder: Encoder) throws {
        // 總是編碼為 Decimal（新格式）
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quantity, forKey: .quantity)
        // ...
    }
}
```

### 7.3 新增欄位相容

新增的 optional 欄位自動向後相容：

```swift
public let dividendInfo: DividendInfo?  // nil = 舊資料
public let feeInfo: FeeInfo?            // nil = 舊資料
```

---

## 八、待確認問題

（無）

---

## 九、預期結果

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
