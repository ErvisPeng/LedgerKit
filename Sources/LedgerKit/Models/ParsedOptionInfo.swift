import Foundation

// MARK: - OptionType

/// The type of option contract.
public enum OptionType: String, Sendable, Codable, CaseIterable {
    case call = "C"
    case put = "P"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .call: return "Call"
        case .put: return "Put"
        }
    }
}

// MARK: - ParsedOptionInfo

/// Information about an options contract.
public struct ParsedOptionInfo: Sendable, Equatable, Hashable, Codable {
    /// The underlying stock ticker (e.g., "AAPL").
    public let underlyingTicker: String

    /// Whether this is a call or put option.
    public let optionType: OptionType

    /// The strike price of the option.
    public let strikePrice: Double

    /// The expiration date of the option.
    public let expirationDate: Date

    /// Creates a new ParsedOptionInfo instance.
    public init(
        underlyingTicker: String,
        optionType: OptionType,
        strikePrice: Double,
        expirationDate: Date
    ) {
        self.underlyingTicker = underlyingTicker
        self.optionType = optionType
        self.strikePrice = strikePrice
        self.expirationDate = expirationDate
    }
}

// MARK: - Computed Properties

public extension ParsedOptionInfo {

    /// Generates a Yahoo Finance compatible option symbol.
    ///
    /// Format: `TICKER` + `YYMMDD` + `C/P` + `00000000` (strike * 1000, padded)
    /// Example: AAPL251219C00150000 (AAPL Dec 19, 2025 $150 Call)
    var yahooSymbol: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = dateFormatter.string(from: expirationDate)

        let strikeInt = Int(strikePrice * 1000)
        let strikeString = String(format: "%08d", strikeInt)

        return "\(underlyingTicker)\(dateString)\(optionType.rawValue)\(strikeString)"
    }

    /// A human-readable display symbol for the option.
    ///
    /// Format: `TICKER` `MM/DD/YY` `$STRIKE` `Call/Put`
    /// Example: AAPL 12/19/25 $150 Call
    var displaySymbol: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yy"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = dateFormatter.string(from: expirationDate)

        let strikeString: String
        if strikePrice.truncatingRemainder(dividingBy: 1) == 0 {
            strikeString = String(format: "%.0f", strikePrice)
        } else {
            strikeString = String(format: "%.2f", strikePrice)
        }

        return "\(underlyingTicker) \(dateString) $\(strikeString) \(optionType.displayName)"
    }
}
