# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-12-18

### Added

- Initial release of LedgerKit
- **Core Models**
  - `ParsedTrade` - Unified trade representation
  - `ParsedTradeType` - Comprehensive trade type enumeration (stock buy/sell, options, dividends, etc.)
  - `ParsedOptionInfo` - Options-specific information (underlying, strike, expiration)
  - `OptionType` - Call/Put enumeration
- **Charles Schwab Parser**
  - Parse JSON exports from Charles Schwab
  - Support for stock trades (buy/sell)
  - Support for options trades (buy to open/close, sell to open/close)
  - Support for dividends and dividend reinvestment
  - Support for option expirations and assignments
  - Support for symbol exchanges (corporate actions)
  - CUSIP to ticker mapping
- **Firstrade Parser**
  - Parse CSV exports from Firstrade
  - Support for stock trades (buy/sell)
  - Support for options trades with description parsing
  - Support for dividends
  - Support for symbol exchanges
- **BrokerParser Protocol**
  - Unified interface for all broker parsers
  - `parse(_:)` method for simple parsing
  - `parseWithWarnings(_:)` method for detailed results with warnings
- **Error Handling**
  - `CharlesSchwabParserError` for Schwab-specific errors
  - `FirstradeParserError` for Firstrade-specific errors
- **Documentation**
  - Comprehensive README with usage examples
  - Contributing guidelines
  - Code of Conduct

### Notes

- This is an initial release (0.x.x), API may change in future versions
- Tested with real export files from Charles Schwab and Firstrade

[Unreleased]: https://github.com/ErvisPeng/LedgerKit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ErvisPeng/LedgerKit/releases/tag/v0.1.0
