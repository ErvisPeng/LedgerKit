import Foundation

// MARK: - ParsedTrade

/// A unified representation of a parsed trade from any broker.
///
/// This struct provides a common format for trade data regardless of the
/// source broker, making it easy to integrate transaction data into your app.
public struct ParsedTrade: Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this trade.
    public let id: UUID

    /// The type of trade (buy, sell, dividend, etc.).
    public let type: ParsedTradeType

    /// The ticker symbol (e.g., "AAPL", "MSFT").
    public let ticker: String

    /// The quantity of shares or contracts.
    public let quantity: Double

    /// The price per share or contract.
    public let price: Double

    /// The total amount of the transaction.
    public let totalAmount: Double

    /// The date the trade was executed.
    public let tradeDate: Date

    /// Option-specific information, if this is an options trade.
    public let optionInfo: ParsedOptionInfo?

    /// Additional notes or description.
    public let note: String

    /// Identifier for the source broker/file.
    public let rawSource: String

    /// Creates a new ParsedTrade instance.
    public init(
        id: UUID = UUID(),
        type: ParsedTradeType,
        ticker: String,
        quantity: Double,
        price: Double,
        totalAmount: Double,
        tradeDate: Date,
        optionInfo: ParsedOptionInfo? = nil,
        note: String = "",
        rawSource: String = ""
    ) {
        self.id = id
        self.type = type
        self.ticker = ticker
        self.quantity = quantity
        self.price = price
        self.totalAmount = totalAmount
        self.tradeDate = tradeDate
        self.optionInfo = optionInfo
        self.note = note
        self.rawSource = rawSource
    }
}

// MARK: - Computed Properties

public extension ParsedTrade {

    /// Returns the display ticker, using option symbol if applicable.
    var displayTicker: String {
        if let optionInfo {
            return optionInfo.displaySymbol
        }
        return ticker
    }

    /// Returns a human-readable summary of the trade.
    var summary: String {
        let action = type.displayName
        let qty = formattedQuantity
        let symbol = displayTicker
        let amt = formattedTotalAmount
        return "\(action) \(qty) \(symbol) for \(amt)"
    }

    /// Formatted quantity string.
    var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", quantity)
        }
        return String(format: "%.4f", quantity)
    }

    /// Formatted price string.
    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    /// Formatted total amount string.
    var formattedTotalAmount: String {
        String(format: "$%.2f", abs(totalAmount))
    }
}
