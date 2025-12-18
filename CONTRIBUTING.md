# Contributing to LedgerKit

Thank you for your interest in contributing to LedgerKit! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:

1. A clear, descriptive title
2. Steps to reproduce the issue
3. Expected behavior vs actual behavior
4. Sample data (anonymized) that causes the issue
5. Your environment (Swift version, platform, etc.)

**Important**: When sharing sample data, please remove or anonymize any personal or financial information.

### Suggesting Features

Feature requests are welcome! Please create an issue with:

1. A clear description of the feature
2. Use cases for the feature
3. Any relevant examples or mockups

### Adding a New Broker

We welcome contributions to add support for new brokers! Here's how:

#### 1. Create the Parser Directory

```
Sources/LedgerKit/Parsers/YourBroker/
├── YourBrokerParser.swift
├── YourBrokerRawRecord.swift  (if needed)
└── YourBrokerActionType.swift (if needed)
```

#### 2. Implement the BrokerParser Protocol

```swift
import Foundation

public final class YourBrokerParser: BrokerParser, Sendable {

    public static let brokerName = "Your Broker"
    public static let supportedFormats: [FileFormat] = [.csv]  // or [.json]

    public init() {}

    public func parse(_ data: Data) throws -> [ParsedTrade] {
        let (trades, _) = try parseWithWarnings(data)
        return trades
    }

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        // Your parsing logic here
        var trades: [ParsedTrade] = []
        var warnings: [String] = []

        // Parse the data...

        return (trades, warnings)
    }
}
```

#### 3. Create Error Types

```swift
// Sources/LedgerKit/Errors/YourBrokerError.swift

public enum YourBrokerParserError: Error, Sendable {
    case invalidFormat
    case missingRequiredField(String)
    case invalidDateFormat(String)
    // Add broker-specific errors
}
```

#### 4. Add Unit Tests

Create comprehensive tests in `Tests/LedgerKitTests/YourBroker/`:

```swift
import Testing
@testable import LedgerKit

struct YourBrokerParserTests {

    let parser = YourBrokerParser()

    @Test func parseStockBuy() throws {
        let data = """
        // Your sample data
        """.data(using: .utf8)!

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .stockBuy)
        #expect(trades[0].ticker == "AAPL")
    }

    // Add more tests...
}
```

#### 5. Update SupportedBroker Enum

Add your broker to `Sources/LedgerKit/Core/SupportedBroker.swift`:

```swift
public enum SupportedBroker: String, CaseIterable, Sendable {
    case charlesSchwab = "Charles Schwab"
    case firstrade = "Firstrade"
    case yourBroker = "Your Broker"  // Add this
}
```

#### 6. Update Documentation

- Add your broker to the README.md supported brokers table
- Include export instructions for your broker
- Update CHANGELOG.md

### Pull Request Process

1. **Fork the repository** and create your branch from `main`
2. **Write tests** for any new functionality
3. **Ensure all tests pass**: `swift test`
4. **Follow the coding style** of the project
5. **Update documentation** as needed
6. **Create a pull request** with a clear description

### Coding Guidelines

#### Swift Style

- Use Swift 5.9+ features
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Add documentation comments for public APIs

#### Code Quality

- All public types must be `Sendable` for concurrency safety
- Use `public` access level only for types meant to be used externally
- Handle errors gracefully with descriptive error types
- Avoid force unwrapping (`!`) - use `guard` or `if let`

#### Testing

- Write tests for all new functionality
- Use Swift Testing framework (`import Testing`)
- Include edge cases and error scenarios
- Use realistic sample data (anonymized)

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/ErvisPeng/LedgerKit.git
   cd LedgerKit
   ```

2. Build the project:
   ```bash
   swift build
   ```

3. Run tests:
   ```bash
   swift test
   ```

### Commit Messages

Use clear, descriptive commit messages:

- `feat: Add YourBroker CSV parser`
- `fix: Handle empty quantity in Firstrade parser`
- `docs: Update README with new broker instructions`
- `test: Add edge case tests for options parsing`
- `refactor: Extract common date parsing logic`

## Questions?

If you have questions, feel free to:

1. Open an issue for discussion
2. Check existing issues and pull requests

Thank you for contributing!
