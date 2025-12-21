import Foundation
import Testing
@testable import LedgerKit

@Suite("CharlesSchwabParser Tests")
struct CharlesSchwabParserTests {

    // MARK: - Test Data

    private func makeJSONData(transactions: [[String: String]]) -> Data {
        let file: [String: Any] = [
            "FromDate": "01/01/2025",
            "ToDate": "12/31/2025",
            "TotalTransactionsAmount": "$0.00",
            "BrokerageTransactions": transactions
        ]
        return try! JSONSerialization.data(withJSONObject: file, options: [])
    }

    private func makeTransaction(
        date: String = "01/15/2025",
        action: String,
        symbol: String,
        description: String = "",
        quantity: String = "0",
        price: String = "$0.00",
        feesAndComm: String = "$0.00",
        amount: String = "$0.00",
        itemIssueId: String = ""
    ) -> [String: String] {
        [
            "Date": date,
            "Action": action,
            "Symbol": symbol,
            "Description": description,
            "Quantity": quantity,
            "Price": price,
            "Fees & Comm": feesAndComm,
            "Amount": amount,
            "ItemIssueId": itemIssueId,
            "AcctgRuleCd": ""
        ]
    }

    // MARK: - Parser Instance

    private let parser = CharlesSchwabParser()

    // MARK: - JSON Parsing Tests

    @Test("Valid JSON is parsed successfully")
    func validJSONParsed() throws {
        let transaction = makeTransaction(
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "100",
            price: "$150.50",
            amount: "-$15,050.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let records = try parser.parseJSON(data)

        #expect(records.count == 1)
        #expect(records[0].symbol == "AAPL")
        #expect(records[0].action == "Buy")
    }

    @Test("Invalid JSON throws error")
    func invalidJSONThrows() {
        let data = "{ invalid json }".data(using: .utf8)!

        #expect(throws: CharlesSchwabParserError.self) {
            _ = try parser.parseJSON(data)
        }
    }

    @Test("Empty transactions array is valid")
    func emptyTransactionsValid() throws {
        let data = makeJSONData(transactions: [])

        let records = try parser.parseJSON(data)

        #expect(records.isEmpty)
    }

    // MARK: - Stock Trade Parsing Tests

    @Test("Stock buy is parsed correctly")
    func stockBuyParsed() throws {
        let transaction = makeTransaction(
            date: "01/15/2025",
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "100",
            price: "$150.50",
            amount: "-$15,050.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockBuy)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 100)
        #expect(trade.price == Decimal(string: "150.50"))
        #expect(trade.totalAmount == Decimal(string: "15050.00"))
    }

    @Test("Stock sell is parsed correctly")
    func stockSellParsed() throws {
        let transaction = makeTransaction(
            date: "01/20/2025",
            action: "Sell",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "-50",
            price: "$155.00",
            amount: "$7,750.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockSell)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 50)
        #expect(trade.price == 155)
    }

    // MARK: - Option Trade Parsing Tests

    @Test("Option buy to open is parsed correctly")
    func optionBuyToOpenParsed() throws {
        let transaction = makeTransaction(
            date: "01/10/2025",
            action: "Buy to Open",
            symbol: "AAPL 02/20/2026 150.00 C",
            description: "CALL APPLE INC",
            quantity: "1",
            price: "$5.50",
            amount: "-$550.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .optionBuyToOpen)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 1)
        #expect(trade.price == Decimal(string: "5.50"))
        #expect(trade.optionInfo != nil)
        #expect(trade.optionInfo?.optionType == .call)
        #expect(trade.optionInfo?.strikePrice == 150)
    }

    @Test("Option sell to open is parsed correctly")
    func optionSellToOpenParsed() throws {
        let transaction = makeTransaction(
            date: "01/10/2025",
            action: "Sell to Open",
            symbol: "HIMS 11/07/2025 45.00 P",
            description: "PUT HIMS & HERS HEALTH INC",
            quantity: "-1",
            price: "$3.20",
            amount: "$320.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .optionSellToOpen)
        #expect(trade.ticker == "HIMS")
        #expect(trade.optionInfo?.optionType == .put)
        #expect(trade.optionInfo?.strikePrice == 45)
    }

    @Test("Option buy to close is parsed correctly")
    func optionBuyToCloseParsed() throws {
        let transaction = makeTransaction(
            action: "Buy to Close",
            symbol: "AAPL 02/20/2026 150.00 C",
            description: "CALL APPLE INC",
            quantity: "1",
            price: "$2.00",
            amount: "-$200.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .optionBuyToClose)
    }

    @Test("Option sell to close is parsed correctly")
    func optionSellToCloseParsed() throws {
        let transaction = makeTransaction(
            action: "Sell to Close",
            symbol: "AAPL 02/20/2026 150.00 P",
            description: "PUT APPLE INC",
            quantity: "-1",
            price: "$8.00",
            amount: "$800.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .optionSellToClose)
    }

    // MARK: - Dividend Parsing Tests

    @Test("Cash dividend is parsed correctly")
    func cashDividendParsed() throws {
        let transaction = makeTransaction(
            date: "11/03/2025",
            action: "Cash Dividend",
            symbol: "AAPL",
            description: "APPLE INC CASH DIV ON 100 SHS",
            quantity: "0",
            price: "$0.00",
            amount: "$25.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .dividend)
        #expect(trade.ticker == "AAPL")
        #expect(trade.totalAmount == 25)
        #expect(trade.quantity == 0)
        #expect(trade.price == 0)
        #expect(trade.dividendInfo != nil)
        #expect(trade.dividendInfo?.grossAmount == 25)
        #expect(trade.dividendInfo?.taxWithheld == 0)
    }

    @Test("Qualified dividend is parsed correctly")
    func qualifiedDividendParsed() throws {
        let transaction = makeTransaction(
            action: "Qualified Dividend",
            symbol: "MSFT",
            description: "MICROSOFT CORP QUALIFIED DIV",
            amount: "$50.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .dividend)
        #expect(trades[0].ticker == "MSFT")
    }

    @Test("Zero amount dividend is skipped")
    func zeroDividendSkipped() throws {
        let transaction = makeTransaction(
            action: "Cash Dividend",
            symbol: "AAPL",
            description: "APPLE INC CASH DIV",
            amount: "$0.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.isEmpty)
    }

    // MARK: - Stock Split Tests

    @Test("Stock split is parsed as zero-cost buy")
    func stockSplitParsed() throws {
        let transaction = makeTransaction(
            action: "Stock Split",
            symbol: "NVDA",
            description: "NVIDIA CORP 10-FOR-1 STOCK SPLIT",
            quantity: "90"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockBuy)
        #expect(trade.ticker == "NVDA")
        #expect(trade.quantity == 90)
        #expect(trade.price == 0)
        #expect(trade.totalAmount == 0)
    }

    // MARK: - Reinvest Shares Tests

    @Test("Reinvest shares is parsed as stock buy")
    func reinvestSharesParsed() throws {
        let transaction = makeTransaction(
            action: "Reinvest Shares",
            symbol: "VTI",
            description: "VANGUARD TOTAL STOCK MKT ETF",
            quantity: "0.5",
            price: "$200.00",
            amount: "-$100.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockBuy)
        #expect(trade.ticker == "VTI")
        #expect(trade.quantity == Decimal(string: "0.5"))
    }

    // MARK: - Symbol Exchange Tests

    @Test("Delivered other is parsed as exchange out")
    func deliveredOtherParsed() throws {
        let transaction = makeTransaction(
            action: "Delivered - Other",
            symbol: "CCIV",
            description: "CHURCHILL CAPITAL CORP IV COM CL A 1:1 EXCHANGE",
            quantity: "-100"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .symbolExchangeOut)
        #expect(trades[0].ticker == "CCIV")
        #expect(trades[0].quantity == 100)
    }

    @Test("Received other is parsed as exchange in")
    func receivedOtherParsed() throws {
        let transaction = makeTransaction(
            action: "Received - Other",
            symbol: "LCID",
            description: "LUCID GROUP INC COM",
            quantity: "100"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .symbolExchangeIn)
        #expect(trades[0].ticker == "LCID")
    }

    // MARK: - Dividend + Tax Merge Tests

    @Test("Dividend and NRA Tax Adj with same ItemIssueId are merged")
    func dividendAndTaxMerged() throws {
        let dividendTransaction = makeTransaction(
            date: "11/03/2025",
            action: "Qualified Dividend",
            symbol: "TSM",
            description: "TAIWAN SEMICONDUCTOR MFG CO LTD SPONSORED ADR CASH DIV ON 100 SHS",
            amount: "$73.00",
            itemIssueId: "12345678"
        )
        let taxTransaction = makeTransaction(
            date: "11/03/2025",
            action: "NRA Tax Adj",
            symbol: "TSM",
            description: "TAIWAN SEMICONDUCTOR MFG CO LTD SPONSORED ADR NRA TAX ADJ",
            amount: "-$15.33",
            itemIssueId: "12345678"
        )
        let data = makeJSONData(transactions: [dividendTransaction, taxTransaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .dividend)
        #expect(trade.ticker == "TSM")
        #expect(trade.totalAmount == Decimal(string: "57.67"))
        #expect(trade.dividendInfo != nil)
        #expect(trade.dividendInfo?.grossAmount == 73)
        #expect(trade.dividendInfo?.taxWithheld == Decimal(string: "15.33"))
        #expect(trade.dividendInfo?.netAmount == Decimal(string: "57.67"))
        #expect(trade.dividendInfo?.issueId == "12345678")
    }

    @Test("Standalone NRA Tax Adj without matching dividend is skipped")
    func standaloneTaxSkipped() throws {
        let transaction = makeTransaction(
            action: "NRA Tax Adj",
            symbol: "AAPL",
            description: "NRA TAX ADJUSTMENT",
            amount: "-$5.00",
            itemIssueId: "99999999"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.isEmpty)
    }

    // MARK: - ADR Fee Parsing Tests

    @Test("ADR Mgmt Fee is parsed as fee type")
    func adrMgmtFeeParsed() throws {
        let transaction = makeTransaction(
            date: "11/06/2025",
            action: "ADR Mgmt Fee",
            symbol: "TSM",
            description: "TAIWAN SEMICONDUCTOR MFG CO LTD SPONSORED ADR (SE) ADR FEES",
            amount: "-$2.50"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .fee)
        #expect(trade.ticker == "TSM")
        #expect(trade.totalAmount == Decimal(string: "2.50"))
        #expect(trade.feeInfo != nil)
        #expect(trade.feeInfo?.type == .adrMgmtFee)
        #expect(trade.feeInfo?.amount == Decimal(string: "2.50"))
    }

    @Test("ADR Mgmt Fee extracts ticker from description")
    func adrMgmtFeeExtractsTickerFromDescription() throws {
        let transaction = makeTransaction(
            date: "11/06/2025",
            action: "ADR Mgmt Fee",
            symbol: "",
            description: "ARM HOLDINGS PLC SPONSORED ADS (SE) ADR FEES",
            amount: "-$1.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].ticker == "ARM")
    }

    // MARK: - Skipped Action Types Tests

    @Test("Internal Transfer is skipped")
    func internalTransferSkipped() throws {
        let transaction = makeTransaction(
            action: "Internal Transfer",
            symbol: "",
            description: "TRANSFER FROM CHECKING"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.isEmpty)
    }

    // MARK: - Option Symbol Parsing Tests

    @Test("Call option symbol is parsed correctly")
    func callOptionSymbolParsed() {
        let optionInfo = parser.parseOptionSymbol("AAPL 01/17/2025 150.00 C")

        #expect(optionInfo != nil)
        #expect(optionInfo?.optionType == .call)
        #expect(optionInfo?.underlyingTicker == "AAPL")
        #expect(optionInfo?.strikePrice == 150)
    }

    @Test("Put option symbol is parsed correctly")
    func putOptionSymbolParsed() {
        let optionInfo = parser.parseOptionSymbol("HIMS 11/07/2025 45.00 P")

        #expect(optionInfo != nil)
        #expect(optionInfo?.optionType == .put)
        #expect(optionInfo?.underlyingTicker == "HIMS")
        #expect(optionInfo?.strikePrice == 45)
    }

    @Test("Option symbol with decimal strike is parsed")
    func decimalStrikeOptionParsed() {
        let optionInfo = parser.parseOptionSymbol("LUMN 01/16/2026 5.50 C")

        #expect(optionInfo != nil)
        #expect(optionInfo?.strikePrice == Decimal(string: "5.50"))
    }

    @Test("Invalid option symbol returns nil")
    func invalidOptionSymbolReturnsNil() {
        let optionInfo = parser.parseOptionSymbol("AAPL COMMON STOCK")

        #expect(optionInfo == nil)
    }

    @Test("Option expiration date is parsed correctly")
    func optionExpirationDateParsed() {
        let optionInfo = parser.parseOptionSymbol("HIMS 11/07/2025 45.00 P")

        #expect(optionInfo != nil)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: optionInfo!.expirationDate)
        #expect(components.month == 11)
        #expect(components.day == 7)
        #expect(components.year == 2025)
    }

    // MARK: - Date Parsing Tests

    @Test("Trade date is parsed correctly")
    func tradeDateParsed() throws {
        let transaction = makeTransaction(
            date: "01/15/2025",
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "100",
            price: "$150.00",
            amount: "-$15,000.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: trades[0].tradeDate)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test("Date with 'as of' format is parsed correctly")
    func dateWithAsOfParsed() throws {
        let transaction = makeTransaction(
            date: "01/15/2025 as of 01/14/2025",
            action: "Cash Dividend",
            symbol: "AAPL",
            description: "APPLE INC DIVIDEND",
            amount: "$25.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: trades[0].tradeDate)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    // MARK: - Amount Parsing Tests

    @Test("Amount with comma and dollar sign is parsed")
    func amountWithFormattingParsed() throws {
        let transaction = makeTransaction(
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "1000",
            price: "$150.00",
            amount: "-$150,000.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].totalAmount == 150000)
    }

    // MARK: - CharlesSchwabActionType Properties Tests

    @Test("ActionType shouldImport property")
    func actionTypeShouldImport() {
        #expect(CharlesSchwabActionType.buy.shouldImport == true)
        #expect(CharlesSchwabActionType.sell.shouldImport == true)
        #expect(CharlesSchwabActionType.buyToOpen.shouldImport == true)
        #expect(CharlesSchwabActionType.cashDividend.shouldImport == true)
        #expect(CharlesSchwabActionType.nraTaxAdj.shouldImport == true)  // Used for dividend+tax merge
        #expect(CharlesSchwabActionType.adrMgmtFee.shouldImport == false)  // Handled specially
    }

    @Test("ActionType isOptionTrade property")
    func actionTypeIsOptionTrade() {
        #expect(CharlesSchwabActionType.buyToOpen.isOptionTrade == true)
        #expect(CharlesSchwabActionType.sellToOpen.isOptionTrade == true)
        #expect(CharlesSchwabActionType.buyToClose.isOptionTrade == true)
        #expect(CharlesSchwabActionType.sellToClose.isOptionTrade == true)
        #expect(CharlesSchwabActionType.buy.isOptionTrade == false)
        #expect(CharlesSchwabActionType.sell.isOptionTrade == false)
    }

    @Test("ActionType isDividend property")
    func actionTypeIsDividend() {
        #expect(CharlesSchwabActionType.cashDividend.isDividend == true)
        #expect(CharlesSchwabActionType.qualifiedDividend.isDividend == true)
        #expect(CharlesSchwabActionType.longTermCapGain.isDividend == true)
        #expect(CharlesSchwabActionType.buy.isDividend == false)
    }

    @Test("ActionType toParsedTradeType conversion")
    func actionTypeToParsedTradeType() {
        #expect(CharlesSchwabActionType.buy.toParsedTradeType() == .stockBuy)
        #expect(CharlesSchwabActionType.sell.toParsedTradeType() == .stockSell)
        #expect(CharlesSchwabActionType.buyToOpen.toParsedTradeType() == .optionBuyToOpen)
        #expect(CharlesSchwabActionType.sellToOpen.toParsedTradeType() == .optionSellToOpen)
        #expect(CharlesSchwabActionType.buyToClose.toParsedTradeType() == .optionBuyToClose)
        #expect(CharlesSchwabActionType.sellToClose.toParsedTradeType() == .optionSellToClose)
        #expect(CharlesSchwabActionType.cashDividend.toParsedTradeType() == .dividend)
    }

    // MARK: - BrokerParser Protocol Tests

    @Test("Parser conforms to BrokerParser protocol")
    func parserConformsToBrokerParser() {
        #expect(CharlesSchwabParser.brokerName == "Charles Schwab")
        #expect(CharlesSchwabParser.supportedFormats == [.json])
    }

    @Test("ParseWithWarnings method returns trades and warnings")
    func parseWithWarningsMethodReturnsTrades() throws {
        let transaction = makeTransaction(
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "100",
            price: "$150.00",
            amount: "-$15,000.00"
        )
        let data = makeJSONData(transactions: [transaction])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        #expect(trades.count == 1)
        #expect(warnings.isEmpty)
    }

    // MARK: - Multiple Records Tests

    @Test("Multiple record types are parsed correctly")
    func multipleRecordTypesParsed() throws {
        let buyTransaction = makeTransaction(
            date: "01/10/2025",
            action: "Buy",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "100",
            price: "$150.00",
            amount: "-$15,000.00"
        )
        let sellTransaction = makeTransaction(
            date: "01/15/2025",
            action: "Sell",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "-50",
            price: "$155.00",
            amount: "$7,750.00"
        )
        let dividendTransaction = makeTransaction(
            date: "01/20/2025",
            action: "Cash Dividend",
            symbol: "AAPL",
            description: "APPLE INC DIVIDEND",
            amount: "$25.00"
        )
        let data = makeJSONData(transactions: [buyTransaction, sellTransaction, dividendTransaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 3)

        let types = trades.map { $0.type }
        #expect(types.contains(.stockBuy))
        #expect(types.contains(.stockSell))
        #expect(types.contains(.dividend))
    }

    @Test("Trades are sorted by date with buys before sells")
    func tradesAreSorted() throws {
        let sellTransaction = makeTransaction(
            date: "01/15/2025",
            action: "Sell",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "-50",
            price: "$155.00",
            amount: "$7,750.00"
        )
        let buyTransaction = makeTransaction(
            date: "01/15/2025",
            action: "Buy",
            symbol: "MSFT",
            description: "MICROSOFT CORP",
            quantity: "100",
            price: "$300.00",
            amount: "-$30,000.00"
        )
        // Insert sell first, then buy (same day)
        let data = makeJSONData(transactions: [sellTransaction, buyTransaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 2)
        // Buys should come before sells on the same day
        #expect(trades[0].type == .stockBuy)
        #expect(trades[1].type == .stockSell)
    }
}
