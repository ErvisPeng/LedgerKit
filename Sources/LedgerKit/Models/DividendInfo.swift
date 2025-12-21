import Foundation

// MARK: - DividendType

/// The type of dividend payment.
public enum DividendType: String, Sendable, Codable, CaseIterable {
    case qualified = "qualified"        // Qualified Dividend
    case ordinary = "ordinary"          // Cash Dividend / Ordinary Dividend
    case capitalGain = "capital_gain"   // Long Term Capital Gain
    case reinvest = "reinvest"          // Dividend Reinvestment
}

// MARK: - DividendInfo

/// Information about a dividend payment, including tax withholding.
public struct DividendInfo: Sendable, Equatable, Hashable, Codable {
    /// The type of dividend.
    public let type: DividendType

    /// The gross dividend amount before tax withholding.
    public let grossAmount: Decimal

    /// The tax withheld (positive value).
    public let taxWithheld: Decimal

    /// The issue ID used for correlating related records (e.g., ItemIssueId).
    public let issueId: String?

    /// Creates a new DividendInfo instance.
    public init(
        type: DividendType,
        grossAmount: Decimal,
        taxWithheld: Decimal = .zero,
        issueId: String? = nil
    ) {
        self.type = type
        self.grossAmount = grossAmount
        self.taxWithheld = taxWithheld
        self.issueId = issueId
    }
}

// MARK: - Computed Properties

public extension DividendInfo {
    /// The net amount received after tax withholding.
    var netAmount: Decimal {
        grossAmount - taxWithheld
    }

    /// Whether any tax was withheld.
    var hasTaxWithheld: Bool {
        taxWithheld > .zero
    }

    /// The effective tax rate as a percentage.
    var effectiveTaxRate: Decimal {
        guard grossAmount > .zero else { return .zero }
        return (taxWithheld / grossAmount) * 100
    }
}
