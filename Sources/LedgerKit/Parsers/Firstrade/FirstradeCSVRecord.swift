import Foundation

// MARK: - FirstradeCSVRecord

/// Raw CSV record from Firstrade transaction history export.
public struct FirstradeCSVRecord: Sendable, Equatable {
    /// Stock symbol (empty for options)
    public let symbol: String

    /// Quantity of shares/contracts (negative for sells)
    public let quantity: Double

    /// Price per share/contract
    public let price: Double

    /// Action type: BUY, SELL, Dividend, Other
    public let action: String

    /// Full description of the transaction
    public let description: String

    /// Trade execution date
    public let tradeDate: Date

    /// Settlement date
    public let settledDate: Date

    /// Interest amount
    public let interest: Double

    /// Total transaction amount
    public let amount: Double

    /// Commission charged
    public let commission: Double

    /// Fee charged
    public let fee: Double

    /// CUSIP identifier
    public let cusip: String

    /// Record type: Trade, Financial
    public let recordType: String

    public init(
        symbol: String,
        quantity: Double,
        price: Double,
        action: String,
        description: String,
        tradeDate: Date,
        settledDate: Date,
        interest: Double,
        amount: Double,
        commission: Double,
        fee: Double,
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
