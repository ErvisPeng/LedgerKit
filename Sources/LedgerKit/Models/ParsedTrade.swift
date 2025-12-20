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
    public let quantity: Decimal

    /// The price per share or contract.
    public let price: Decimal

    /// The total amount of the transaction.
    public let totalAmount: Decimal

    /// The date the trade was executed.
    public let tradeDate: Date

    /// Option-specific information, if this is an options trade.
    public let optionInfo: ParsedOptionInfo?

    /// Dividend-specific information, if this is a dividend payment.
    public let dividendInfo: DividendInfo?

    /// Fee-specific information, if this is a fee charge.
    public let feeInfo: FeeInfo?

    /// Additional notes or description.
    public let note: String

    /// Identifier for the source broker/file.
    public let rawSource: String

    /// Creates a new ParsedTrade instance.
    public init(
        id: UUID = UUID(),
        type: ParsedTradeType,
        ticker: String,
        quantity: Decimal,
        price: Decimal,
        totalAmount: Decimal,
        tradeDate: Date,
        optionInfo: ParsedOptionInfo? = nil,
        dividendInfo: DividendInfo? = nil,
        feeInfo: FeeInfo? = nil,
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
        self.dividendInfo = dividendInfo
        self.feeInfo = feeInfo
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
        let doubleValue = NSDecimalNumber(decimal: quantity).doubleValue
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", doubleValue)
        }
        return String(format: "%.4f", doubleValue)
    }

    /// Formatted price string.
    var formattedPrice: String {
        let doubleValue = NSDecimalNumber(decimal: price).doubleValue
        return String(format: "$%.2f", doubleValue)
    }

    /// Formatted total amount string.
    var formattedTotalAmount: String {
        let doubleValue = NSDecimalNumber(decimal: totalAmount).doubleValue
        return String(format: "$%.2f", abs(doubleValue))
    }
}

// MARK: - Backward Compatibility

public extension ParsedTrade {

    /// Backward compatible quantity as Double.
    @available(*, deprecated, message: "Use quantity (Decimal) instead")
    var quantityDouble: Double {
        NSDecimalNumber(decimal: quantity).doubleValue
    }

    /// Backward compatible price as Double.
    @available(*, deprecated, message: "Use price (Decimal) instead")
    var priceDouble: Double {
        NSDecimalNumber(decimal: price).doubleValue
    }

    /// Backward compatible totalAmount as Double.
    @available(*, deprecated, message: "Use totalAmount (Decimal) instead")
    var totalAmountDouble: Double {
        NSDecimalNumber(decimal: totalAmount).doubleValue
    }
}

// MARK: - Codable

extension ParsedTrade: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case ticker
        case quantity
        case price
        case totalAmount
        case tradeDate
        case optionInfo
        case dividendInfo
        case feeInfo
        case note
        case rawSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ParsedTradeType.self, forKey: .type)
        ticker = try container.decode(String.self, forKey: .ticker)

        // Support both Decimal and Double for backward compatibility
        if let decimal = try? container.decode(Decimal.self, forKey: .quantity) {
            quantity = decimal
        } else {
            let double = try container.decode(Double.self, forKey: .quantity)
            quantity = Decimal(double)
        }

        if let decimal = try? container.decode(Decimal.self, forKey: .price) {
            price = decimal
        } else {
            let double = try container.decode(Double.self, forKey: .price)
            price = Decimal(double)
        }

        if let decimal = try? container.decode(Decimal.self, forKey: .totalAmount) {
            totalAmount = decimal
        } else {
            let double = try container.decode(Double.self, forKey: .totalAmount)
            totalAmount = Decimal(double)
        }

        tradeDate = try container.decode(Date.self, forKey: .tradeDate)
        optionInfo = try container.decodeIfPresent(ParsedOptionInfo.self, forKey: .optionInfo)
        dividendInfo = try container.decodeIfPresent(DividendInfo.self, forKey: .dividendInfo)
        feeInfo = try container.decodeIfPresent(FeeInfo.self, forKey: .feeInfo)
        note = try container.decode(String.self, forKey: .note)
        rawSource = try container.decode(String.self, forKey: .rawSource)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(price, forKey: .price)
        try container.encode(totalAmount, forKey: .totalAmount)
        try container.encode(tradeDate, forKey: .tradeDate)
        try container.encodeIfPresent(optionInfo, forKey: .optionInfo)
        try container.encodeIfPresent(dividendInfo, forKey: .dividendInfo)
        try container.encodeIfPresent(feeInfo, forKey: .feeInfo)
        try container.encode(note, forKey: .note)
        try container.encode(rawSource, forKey: .rawSource)
    }
}
