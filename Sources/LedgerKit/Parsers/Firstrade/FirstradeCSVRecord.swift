import Foundation

// MARK: - FirstradeCSVRecord

/// Raw CSV record from Firstrade transaction history export.
public struct FirstradeCSVRecord: Sendable, Equatable {
    /// Stock symbol (empty for options)
    public let symbol: String

    /// Quantity of shares/contracts (negative for sells)
    public let quantity: Decimal

    /// Price per share/contract
    public let price: Decimal

    /// Action type: BUY, SELL, Dividend, Other
    public let action: String

    /// Full description of the transaction
    public let description: String

    /// Trade execution date
    public let tradeDate: Date

    /// Settlement date
    public let settledDate: Date

    /// Interest amount
    public let interest: Decimal

    /// Total transaction amount
    public let amount: Decimal

    /// Commission charged
    public let commission: Decimal

    /// Fee charged
    public let fee: Decimal

    /// CUSIP identifier
    public let cusip: String

    /// Record type: Trade, Financial
    public let recordType: String

    public init(
        symbol: String,
        quantity: Decimal,
        price: Decimal,
        action: String,
        description: String,
        tradeDate: Date,
        settledDate: Date,
        interest: Decimal,
        amount: Decimal,
        commission: Decimal,
        fee: Decimal,
        cusip: String,
        recordType: String
    ) {
        self.symbol = symbol
        self.quantity = quantity
        self.price = price
        self.action = action
        self.description = description
        self.tradeDate = tradeDate
        self.settledDate = settledDate
        self.interest = interest
        self.amount = amount
        self.commission = commission
        self.fee = fee
        self.cusip = cusip
        self.recordType = recordType
    }
}
