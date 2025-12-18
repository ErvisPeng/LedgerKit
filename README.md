# LedgerKit

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2012+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A Swift library for parsing brokerage transaction data from various brokers into a unified format.

## Features

- Parse transaction history from multiple brokers
- Unified output format for easy integration
- Support for stocks and options trading
- Zero external dependencies (Foundation only)
- Thread-safe with Swift Concurrency support

## Supported Brokers

| Broker | Format | Status |
|--------|--------|--------|
| Charles Schwab | JSON | Coming Soon |
| Firstrade | CSV | Coming Soon |

## Installation

### Swift Package Manager

Add LedgerKit to your project via Xcode:

1. File > Add Package Dependencies
2. Enter the repository URL:
   ```
   https://github.com/ervispeng/LedgerKit.git
   ```
3. Select version: `0.1.0` or later

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ervispeng/LedgerKit.git", from: "0.1.0")
]
```

## Quick Start

```swift
import LedgerKit

// Parse Charles Schwab JSON export
let parser = CharlesSchwabParser()
let trades = try parser.parse(jsonData)

// Parse Firstrade CSV export
let parser = FirstradeParser()
let trades = try parser.parse(csvData)

// All parsers output the same unified format
for trade in trades {
    print("\(trade.tradeDate): \(trade.type) \(trade.quantity) \(trade.ticker) @ \(trade.price)")
}
```

## Output Format

All parsers output `ParsedTrade` objects with a unified structure:

```swift
public struct ParsedTrade {
    public let id: UUID
    public let type: ParsedTradeType      // stockBuy, stockSell, optionBuy, etc.
    public let ticker: String
    public let quantity: Double
    public let price: Double
    public let totalAmount: Double
    public let tradeDate: Date
    public let optionInfo: ParsedOptionInfo?  // For options trades
    public let note: String
}
```

## Adding a New Broker

Want to add support for another broker? See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Requirements

- Swift 5.9+
- iOS 15+ / macOS 12+

## License

LedgerKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.
