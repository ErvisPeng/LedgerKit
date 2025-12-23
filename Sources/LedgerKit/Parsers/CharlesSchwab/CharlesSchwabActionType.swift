import Foundation

// MARK: - CharlesSchwabActionType

/// Charles Schwab transaction action types.
public enum CharlesSchwabActionType: String, Sendable, CaseIterable {
    // Stock trades
    case buy = "Buy"
    case sell = "Sell"

    // Option trades
    case buyToOpen = "Buy to Open"
    case sellToOpen = "Sell to Open"
    case buyToClose = "Buy to Close"
    case sellToClose = "Sell to Close"

    // Dividends
    case cashDividend = "Cash Dividend"
    case qualifiedDividend = "Qualified Dividend"
    case qualDivReinvest = "Qual Div Reinvest"
    case reinvestDividend = "Reinvest Dividend"
    case reinvestShares = "Reinvest Shares"
    case longTermCapGain = "Long Term Cap Gain"

    // Tax/Fees (handled specially in parser)
    case nraTaxAdj = "NRA Tax Adj"
    case adrMgmtFee = "ADR Mgmt Fee"

    // Symbol exchange / Corporate actions
    case deliveredOther = "Delivered - Other"
    case receivedOther = "Received - Other"
    case journaledShares = "Journaled Shares"
    case mandatoryReorgExc = "Mandatory Reorg Exc"

    // Cash flow
    case fundsDeposited = "Funds Deposited"
    case fundsWithdrawn = "Funds Withdrawn"
    case divIntIncome = "Div/Int - Income"
    case divIntExpense = "Div/Int - Expense"
    case journalOther = "Journal - Other"
    case marginInterest = "Margin Interest"

    // Other (skip)
    case stockSplit = "Stock Split"
    case cashInLieu = "Cash In Lieu"
    case internalTransfer = "Internal Transfer"
    case moneyLinkDeposit = "MoneyLink Deposit"
    case moneyLinkTransfer = "MoneyLink Transfer"
    case creditInterest = "Credit Interest"
    case bondInterest = "Bond Interest"
    case interestAdj = "Interest Adj"

    /// Initialize from raw action string.
    public init?(rawAction: String) {
        if let type = CharlesSchwabActionType(rawValue: rawAction) {
            self = type
        } else {
            return nil
        }
    }

    /// Whether this action type should be imported.
    public var shouldImport: Bool {
        switch self {
        case .buy, .sell,
             .buyToOpen, .sellToOpen, .buyToClose, .sellToClose,
             .cashDividend, .qualifiedDividend, .qualDivReinvest, .reinvestDividend, .reinvestShares, .longTermCapGain,
             .stockSplit,
             .deliveredOther, .receivedOther, .journaledShares, .mandatoryReorgExc,
             .moneyLinkDeposit, .moneyLinkTransfer, .internalTransfer,
             .fundsDeposited, .fundsWithdrawn,
             .divIntIncome, .divIntExpense,
             .journalOther, .marginInterest,
             .nraTaxAdj, .bondInterest, .creditInterest,
             .cashInLieu, .interestAdj:
            return true
        default:
            return false
        }
    }

    /// Whether this is a symbol exchange / corporate action.
    public var isSymbolExchange: Bool {
        switch self {
        case .deliveredOther, .receivedOther, .journaledShares, .mandatoryReorgExc:
            return true
        default:
            return false
        }
    }

    /// Whether this is an option trade.
    public var isOptionTrade: Bool {
        switch self {
        case .buyToOpen, .sellToOpen, .buyToClose, .sellToClose:
            return true
        default:
            return false
        }
    }

    /// Whether this is a buy action.
    public var isBuyAction: Bool {
        switch self {
        case .buy, .buyToOpen, .buyToClose, .reinvestShares, .stockSplit:
            return true
        default:
            return false
        }
    }

    /// Whether this is a sell action.
    public var isSellAction: Bool {
        switch self {
        case .sell, .sellToOpen, .sellToClose:
            return true
        default:
            return false
        }
    }

    /// Whether this is a dividend action.
    public var isDividend: Bool {
        switch self {
        case .cashDividend, .qualifiedDividend, .longTermCapGain:
            return true
        default:
            return false
        }
    }

    /// Whether this opens a position.
    public var isOpenPosition: Bool {
        switch self {
        case .buyToOpen, .sellToOpen:
            return true
        default:
            return false
        }
    }

    /// Whether this closes a position.
    public var isClosePosition: Bool {
        switch self {
        case .buyToClose, .sellToClose:
            return true
        default:
            return false
        }
    }

    /// Convert to ParsedTradeType.
    public func toParsedTradeType() -> ParsedTradeType? {
        switch self {
        case .buy, .reinvestShares, .stockSplit:
            return .stockBuy
        case .sell:
            return .stockSell
        case .buyToOpen:
            return .optionBuyToOpen
        case .buyToClose:
            return .optionBuyToClose
        case .sellToOpen:
            return .optionSellToOpen
        case .sellToClose:
            return .optionSellToClose
        case .cashDividend, .qualifiedDividend, .longTermCapGain:
            return .dividend
        case .qualDivReinvest, .reinvestDividend:
            return .dividendReinvest
        case .moneyLinkDeposit, .moneyLinkTransfer, .fundsDeposited:
            // Note: Caller should check amount to determine deposit vs withdraw
            return .deposit
        case .fundsWithdrawn:
            return .withdraw
        case .bondInterest, .creditInterest:
            return .interestIncome
        case .nraTaxAdj, .journalOther:
            return .taxWithholding
        case .divIntIncome, .cashInLieu:
            // Note: Could be dividend or interest - parser will determine
            // cashInLieu: fractional share cash payment from stock split/merger
            return .dividend
        case .divIntExpense, .marginInterest, .interestAdj:
            return .fee
        default:
            return nil
        }
    }
}
