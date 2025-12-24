import Foundation

// MARK: - ParsedTradeType

/// The type of trade transaction.
public enum ParsedTradeType: String, Sendable, CaseIterable, Codable {
    // Stock trades
    case stockBuy = "stock_buy"
    case stockSell = "stock_sell"

    // Option trades (generic)
    case optionBuy = "option_buy"
    case optionSell = "option_sell"

    // Option trades (specific open/close)
    case optionBuyToOpen = "option_buy_to_open"
    case optionBuyToClose = "option_buy_to_close"
    case optionSellToOpen = "option_sell_to_open"
    case optionSellToClose = "option_sell_to_close"

    // Other transaction types
    case dividend = "dividend"
    case dividendReinvest = "dividend_reinvest"
    case symbolExchangeOut = "symbol_exchange_out"
    case symbolExchangeIn = "symbol_exchange_in"
    case optionExpiration = "option_expiration"
    case optionAssignment = "option_assignment"
    case fee = "fee"

    // Cash transfer types
    case deposit = "deposit"
    case withdraw = "withdraw"

    // Other income/expense types
    case interestIncome = "interest_income"
    case marginInterest = "margin_interest"
    case taxWithholding = "tax_withholding"

    /// Whether this trade type represents a buy action.
    public var isBuy: Bool {
        switch self {
        case .stockBuy, .optionBuy, .optionBuyToOpen, .optionBuyToClose, .dividendReinvest, .symbolExchangeIn:
            return true
        default:
            return false
        }
    }

    /// Whether this trade type represents a sell action.
    public var isSell: Bool {
        switch self {
        case .stockSell, .optionSell, .optionSellToOpen, .optionSellToClose, .symbolExchangeOut:
            return true
        default:
            return false
        }
    }

    /// Whether this trade type is for options.
    public var isOption: Bool {
        switch self {
        case .optionBuy, .optionSell, .optionBuyToOpen, .optionBuyToClose,
             .optionSellToOpen, .optionSellToClose, .optionExpiration, .optionAssignment:
            return true
        default:
            return false
        }
    }

    /// Whether this trade type opens a position.
    public var isOpenPosition: Bool {
        switch self {
        case .stockBuy, .optionBuyToOpen, .optionSellToOpen:
            return true
        default:
            return false
        }
    }

    /// Whether this trade type closes a position.
    public var isClosePosition: Bool {
        switch self {
        case .stockSell, .optionBuyToClose, .optionSellToClose, .optionExpiration, .optionAssignment:
            return true
        default:
            return false
        }
    }

    /// Whether this trade type is a cash transfer.
    public var isCashTransfer: Bool {
        switch self {
        case .deposit, .withdraw:
            return true
        default:
            return false
        }
    }

    /// A human-readable display name for the trade type.
    public var displayName: String {
        switch self {
        case .stockBuy: return "Buy"
        case .stockSell: return "Sell"
        case .optionBuy: return "Buy Option"
        case .optionSell: return "Sell Option"
        case .optionBuyToOpen: return "Buy to Open"
        case .optionBuyToClose: return "Buy to Close"
        case .optionSellToOpen: return "Sell to Open"
        case .optionSellToClose: return "Sell to Close"
        case .dividend: return "Dividend"
        case .dividendReinvest: return "Dividend Reinvest"
        case .symbolExchangeOut: return "Exchange Out"
        case .symbolExchangeIn: return "Exchange In"
        case .optionExpiration: return "Option Expired"
        case .optionAssignment: return "Option Assigned"
        case .fee: return "Fee"
        case .deposit: return "Deposit"
        case .withdraw: return "Withdraw"
        case .interestIncome: return "Interest Income"
        case .marginInterest: return "Margin Interest"
        case .taxWithholding: return "Tax Withholding"
        }
    }
}
