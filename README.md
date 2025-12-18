# LedgerKit

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2012+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/ErvisPeng/LedgerKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ErvisPeng/LedgerKit/actions/workflows/ci.yml)

A Swift library for parsing brokerage transaction data from various brokers into a unified format.

## Features

- **Multi-Broker Support** - Parse transaction history from Charles Schwab (JSON) and Firstrade (CSV)
- **Unified Output** - All brokers output the same `ParsedTrade` format for easy integration
- **Options Support** - Full support for options trading including calls, puts, assignments, and expirations
- **Type-Safe** - Strongly typed trade types and error handling
- **Zero Dependencies** - Built on Foundation only, no external dependencies
- **Thread-Safe** - Full Swift Concurrency support with `Sendable` conformance

## Supported Brokers

| Broker | Format | Status | Notes |
|--------|--------|--------|-------|
| Charles Schwab | JSON | ✅ Supported | Export from Schwab website |
| Firstrade | CSV | ✅ Supported | Export from Firstrade website |

## Installation

### Swift Package Manager

Add LedgerKit to your project via Xcode:

1. **File** > **Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/ErvisPeng/LedgerKit.git
   ```
3. Select version: `0.1.0` or later

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ErvisPeng/LedgerKit.git", from: "0.1.0")
]
```

Then add `LedgerKit` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["LedgerKit"]
)
```

## Quick Start

### Parsing Charles Schwab JSON

```swift
import LedgerKit

// Load your exported JSON file
let jsonData = try Data(contentsOf: schwabExportURL)

// Parse the transactions
let parser = CharlesSchwabParser()
let trades = try parser.parse(jsonData)

// Use the parsed trades
for trade in trades {
    print("\(trade.tradeDate): \(trade.type) \(trade.quantity) \(trade.ticker)")
}
```

### Parsing Firstrade CSV

```swift
import LedgerKit

// Load your exported CSV file
let csvData = try Data(contentsOf: firstradeExportURL)

// Parse the transactions
let parser = FirstradeParser()
let trades = try parser.parse(csvData)
```

### Getting Warnings

Some transactions may generate warnings (e.g., unrecognized action types). Use `parseWithWarnings` to capture them:

```swift
let parser = CharlesSchwabParser()
let (trades, warnings) = try parser.parseWithWarnings(jsonData)

for warning in warnings {
    print("Warning: \(warning)")
}
```

## Output Format

All parsers output `ParsedTrade` objects with a unified structure:

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

### Trade Types

```swift
public enum ParsedTradeType: String, Sendable {
    // Stock trades
    case stockBuy
    case stockSell

    // Option trades
    case optionBuy
    case optionSell
    case optionBuyToOpen
    case optionBuyToClose
    case optionSellToOpen
    case optionSellToClose
    case optionExpiration
    case optionAssignment

    // Income
    case dividend
    case dividendReinvest

    // Corporate actions
    case symbolExchangeIn
    case symbolExchangeOut
}
```

### Options Information

For options trades, `ParsedTrade.optionInfo` contains:

```swift
public struct ParsedOptionInfo: Sendable, Equatable {
    public let underlyingTicker: String  // e.g., "AAPL"
    public let optionType: OptionType    // .call or .put
    public let strikePrice: Double       // e.g., 150.0
    public let expirationDate: Date
}
```

## Error Handling

Each parser has its own error type for specific error cases:

```swift
do {
    let trades = try parser.parse(data)
} catch let error as CharlesSchwabParserError {
    switch error {
    case .invalidJSON:
        print("Invalid JSON format")
    case .missingRequiredField(let field):
        print("Missing field: \(field)")
    case .invalidDateFormat(let dateString):
        print("Invalid date: \(dateString)")
    }
} catch let error as FirstradeParserError {
    switch error {
    case .invalidCSVFormat:
        print("Invalid CSV format")
    case .missingHeader:
        print("CSV header not found")
    case .invalidDateFormat(let dateString):
        print("Invalid date: \(dateString)")
    }
}
```

## How to Export Transaction History

### Charles Schwab

1. Log in to [schwab.com](https://www.schwab.com)
2. Go to **Accounts** > **History**
3. Select date range and click **Export**
4. Choose **JSON** format

### Firstrade

1. Log in to [firstrade.com](https://www.firstrade.com)
2. Go to **Accounts** > **History**
3. Select date range and click **Download**
4. Choose **CSV** format

## Adding a New Broker

Want to add support for another broker? LedgerKit is designed to be extensible.

1. Create a new parser class implementing `BrokerParser` protocol
2. Add broker-specific record types if needed
3. Add unit tests with sample data
4. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Requirements

- Swift 5.9+
- iOS 15+ / macOS 12+

## License

LedgerKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## Acknowledgments

- Inspired by the need for a unified way to import brokerage data into personal finance apps
- Built with Swift best practices and modern concurrency support
