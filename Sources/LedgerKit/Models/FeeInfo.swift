import Foundation

// MARK: - FeeType

/// The type of fee.
public enum FeeType: String, Sendable, Codable, CaseIterable {
    case adrMgmtFee = "adr_mgmt_fee"  // ADR Management Fee
    case tradingCommission = "trading_commission"  // Trading Commission
    case taxWithholding = "tax_withholding"  // Tax Withholding (NRA, W-8, etc.)
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
        }
    }
}
