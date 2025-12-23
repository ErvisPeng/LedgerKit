import Foundation

// MARK: - FeeType

/// The type of fee.
public enum FeeType: String, Sendable, Codable, CaseIterable {
    case adrMgmtFee = "adr_mgmt_fee"              // ADR Management Fee
    case tradingCommission = "trading_commission"  // Trading Commission
    case taxWithholding = "tax_withholding"        // Tax Withholding (NRA, W-8, etc.)
    case wireFee = "wire_fee"                      // Wire Transfer Fee
    case achFee = "ach_fee"                        // ACH Fee
    case foreignTransactionFee = "foreign_tx_fee"  // Foreign Transaction Fee (ATM/Debit Card)
    case other = "other"                           // Other Fees (including rebates)
}

// MARK: - FeeInfo

/// Information about a fee charge.
public struct FeeInfo: Sendable, Equatable, Hashable, Codable {
    /// The type of fee.
    public let type: FeeType

    /// The fee amount (positive value).
    public let amount: Decimal

    /// Creates a new FeeInfo instance.
    public init(
        type: FeeType,
        amount: Decimal
    ) {
        self.type = type
        self.amount = amount
    }
}

// MARK: - Computed Properties

public extension FeeInfo {
    /// A human-readable display name for the fee type.
    var displayName: String {
        switch type {
        case .adrMgmtFee:
            return "ADR Management Fee"
        case .tradingCommission:
            return "Trading Commission"
        case .taxWithholding:
            return "Tax Withholding"
        case .wireFee:
            return "Wire Transfer Fee"
        case .achFee:
            return "ACH Fee"
        case .foreignTransactionFee:
            return "Foreign Transaction Fee"
        case .other:
            return "Other Fee"
        }
    }
}
