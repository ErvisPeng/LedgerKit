import Foundation

// MARK: - CharlesSchwabTransactionFile

/// Charles Schwab transaction history JSON file structure.
public struct CharlesSchwabTransactionFile: Codable, Sendable {
    public let fromDate: String
    public let toDate: String
    public let totalTransactionsAmount: String
    public let brokerageTransactions: [CharlesSchwabRawTransaction]

    enum CodingKeys: String, CodingKey {
        case fromDate = "FromDate"
        case toDate = "ToDate"
        case totalTransactionsAmount = "TotalTransactionsAmount"
        case brokerageTransactions = "BrokerageTransactions"
    }

    public init(
        fromDate: String,
        toDate: String,
        totalTransactionsAmount: String,
        brokerageTransactions: [CharlesSchwabRawTransaction]
    ) {
        self.fromDate = fromDate
        self.toDate = toDate
        self.totalTransactionsAmount = totalTransactionsAmount
        self.brokerageTransactions = brokerageTransactions
    }
}

// MARK: - CharlesSchwabRawTransaction

/// Raw transaction record from Charles Schwab JSON export.
public struct CharlesSchwabRawTransaction: Codable, Sendable, Equatable {
    public let date: String
    public let action: String
    public let symbol: String
    public let description: String
    public let quantity: String
    public let price: String
    public let feesAndComm: String
    public let amount: String
    public let itemIssueId: String
    public let acctgRuleCd: String

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case action = "Action"
        case symbol = "Symbol"
        case description = "Description"
        case quantity = "Quantity"
        case price = "Price"
        case feesAndComm = "Fees & Comm"
        case amount = "Amount"
        case itemIssueId = "ItemIssueId"
        case acctgRuleCd = "AcctgRuleCd"
    }

    public init(
        date: String,
        action: String,
        symbol: String,
        description: String,
        quantity: String,
        price: String,
        feesAndComm: String,
        amount: String,
        itemIssueId: String = "",
        acctgRuleCd: String = ""
    ) {
        self.date = date
        self.action = action
        self.symbol = symbol
        self.description = description
        self.quantity = quantity
        self.price = price
        self.feesAndComm = feesAndComm
        self.amount = amount
        self.itemIssueId = itemIssueId
        self.acctgRuleCd = acctgRuleCd
    }
}
