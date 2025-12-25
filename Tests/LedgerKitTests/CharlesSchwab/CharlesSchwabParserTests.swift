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
        #expect(trade.totalAmount == Decimal(string: "-15050.00"))  // Negative for buys
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

    @Test("Stock sell with commission has feeInfo")
    func stockSellWithCommissionParsed() throws {
        let transaction = makeTransaction(
            date: "01/20/2025",
            action: "Sell",
            symbol: "AAPL",
            description: "APPLE INC",
            quantity: "-50",
            price: "$155.00",
            feesAndComm: "$0.01",
            amount: "$7,749.99"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockSell)
        #expect(trade.totalAmount == Decimal(string: "7749.99"))  // Positive for sells
        #expect(trade.feeInfo != nil)
        #expect(trade.feeInfo?.type == .tradingCommission)
        #expect(trade.feeInfo?.amount == Decimal(string: "0.01"))
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

    @Test("Standalone NRA Tax Adj without matching dividend is parsed as taxWithholding")
    func standaloneTaxParsed() throws {
        let transaction = makeTransaction(
            action: "NRA Tax Adj",
            symbol: "AAPL",
            description: "NRA TAX ADJUSTMENT",
            amount: "-$5.00",
            itemIssueId: "99999999"
        )
        let data = makeJSONData(transactions: [transaction])

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .taxWithholding)
        #expect(trades[0].ticker == "AAPL")
        #expect(trades[0].totalAmount == Decimal(string: "-5.00"))
    }

    @Test("Buy and Sell are not skipped when sharing ItemIssueId with dividend")
    func buySellNotSkippedWithSameIssueId() throws {
        // This test verifies the bug fix: previously, when a dividend+tax pair was found,
        // all other records in the same ItemIssueId group were skipped.
        let buyTransaction = makeTransaction(
            date: "01/02/2025",
            action: "Buy",
            symbol: "NVDA",
            description: "NVIDIA CORP",
            quantity: "100",
            price: "$120.00",
            amount: "-$12,000.00",
            itemIssueId: "382397811"  // Same ItemIssueId as dividend below
        )
        let sellTransaction = makeTransaction(
            date: "01/15/2025",
            action: "Sell",
            symbol: "NVDA",
            description: "NVIDIA CORP",
            quantity: "50",
            price: "$130.00",
            amount: "$6,500.00",
            itemIssueId: "382397811"  // Same ItemIssueId
        )
        let dividendTransaction = makeTransaction(
            date: "12/27/2024",
            action: "Qualified Dividend",
            symbol: "NVDA",
            description: "NVIDIA CORP",
            amount: "$2.87",
            itemIssueId: "382397811"  // Same ItemIssueId
        )
        let taxTransaction = makeTransaction(
            date: "12/27/2024",
            action: "NRA Tax Adj",
            symbol: "NVDA",
            description: "NVIDIA CORP",
            amount: "-$0.86",
            itemIssueId: "382397811"  // Same ItemIssueId
        )
        let data = makeJSONData(transactions: [
            buyTransaction,
            sellTransaction,
            dividendTransaction,
            taxTransaction
        ])

        let trades = try parser.parse(data)

        // All 3 trades should be parsed (dividend + tax merged into 1)
        #expect(trades.count == 3)

        // Verify each type exists
        let types = Set(trades.map { $0.type })
        #expect(types.contains(.stockBuy))
        #expect(types.contains(.stockSell))
        #expect(types.contains(.dividend))

        // Verify dividend has correct tax merged
        let dividend = trades.first { $0.type == .dividend }
        #expect(dividend?.dividendInfo?.grossAmount == Decimal(string: "2.87"))
        #expect(dividend?.dividendInfo?.taxWithheld == Decimal(string: "0.86"))
        #expect(dividend?.totalAmount == Decimal(string: "2.01"))

        // Verify buy/sell amounts
        let buy = trades.first { $0.type == .stockBuy }
        #expect(buy?.totalAmount == -12000)  // Negative for buys
        let sell = trades.first { $0.type == .stockSell }
        #expect(sell?.totalAmount == 6500)
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
        #expect(trade.totalAmount == Decimal(string: "-2.50"))  // Fee is cash outflow (negative)
        #expect(trade.feeInfo != nil)
        #expect(trade.feeInfo?.type == .adrMgmtFee)
        #expect(trade.feeInfo?.amount == Decimal(string: "2.50"))  // feeInfo.amount is absolute value
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
        #expect(trades[0].totalAmount == -150000)  // Negative for buys
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

    // MARK: - CUSIP Resolution Tests

    @Test("CUSIP symbol is resolved to ticker via company name")
    func cusipResolvedToTicker() throws {
        // Scenario: SPAC merger - original buy has ticker, delivered has CUSIP
        let buyTransaction = makeTransaction(
            date: "02/24/2021",
            action: "Buy",
            symbol: "CAPA",
            description: "HIGHCAPE CAP ACQUISITION CORP COM CL A",
            quantity: "2",
            price: "$10.00",
            amount: "-$20.00"
        )
        let deliveredTransaction = makeTransaction(
            date: "06/11/2021",
            action: "Delivered - Other",
            symbol: "42984L105",  // CUSIP instead of ticker
            description: "HIGHCAPE CAP ACQUISITION CORP 1:1 R/S 6/1//21 74765K105 1:1 EXCHANGE TO QUANTUM-SI INC 74765K105 Auto Reorg#537627ISTOCK PAYMENT",
            quantity: "-2"
        )
        let data = makeJSONData(transactions: [buyTransaction, deliveredTransaction])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        // Should have 2 trades: buy + exchange out
        #expect(trades.count == 2, "Expected 2 trades but got \(trades.count)")

        // Verify the exchange out uses the resolved ticker
        let exchangeOut = trades.first { $0.type == .symbolExchangeOut }
        #expect(exchangeOut != nil, "Expected symbolExchangeOut trade")
        #expect(exchangeOut?.ticker == "CAPA", "Expected ticker CAPA but got \(exchangeOut?.ticker ?? "nil")")

        // Should have no warnings
        #expect(warnings.isEmpty, "Expected no warnings but got: \(warnings)")
    }

    @Test("Company name normalization handles CORP vs CO variation")
    func companyNameNormalizationHandlesCorpVsCo() throws {
        // First record has "CORP", second has "CO" - should match after normalization
        let buyTransaction = makeTransaction(
            date: "01/01/2021",
            action: "Buy",
            symbol: "STPK",
            description: "STAR PEAK ENERGY TRANSITION CORP COM CL A",
            quantity: "10",
            price: "$20.00",
            amount: "-$200.00"
        )
        let deliveredTransaction = makeTransaction(
            date: "04/29/2021",
            action: "Delivered - Other",
            symbol: "85859N102",  // CUSIP
            description: "STAR PEAK ENERGY TRANSITION CO 1:1 EXC 4/29/21 85859N102 1:1 EXCHANGE TO STEM INC 85859N102 Auto Reorg#530199ISTOCK PAYMENT",
            quantity: "-10"
        )
        let data = makeJSONData(transactions: [buyTransaction, deliveredTransaction])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        // Should resolve CUSIP to ticker despite CORP vs CO difference
        #expect(trades.count == 2, "Expected 2 trades but got \(trades.count)")

        let exchangeOut = trades.first { $0.type == .symbolExchangeOut }
        #expect(exchangeOut != nil, "Expected symbolExchangeOut trade")
        #expect(exchangeOut?.ticker == "STPK", "Expected ticker STPK but got \(exchangeOut?.ticker ?? "nil")")

        #expect(warnings.isEmpty, "Expected no warnings but got: \(warnings)")
    }

    @Test("CUSIP without matching buy record generates warning")
    func cusipWithoutMatchingBuyGeneratesWarning() throws {
        // Only has delivered record with CUSIP, no buy to resolve against
        let deliveredTransaction = makeTransaction(
            date: "06/11/2021",
            action: "Delivered - Other",
            symbol: "42984L105",  // CUSIP
            description: "UNKNOWN COMPANY 1:1 EXCHANGE TO SOMETHING",
            quantity: "-2"
        )
        let data = makeJSONData(transactions: [deliveredTransaction])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        // Should not create a trade
        #expect(trades.isEmpty, "Expected no trades but got \(trades.count)")

        // Should have a warning about unresolved CUSIP
        #expect(warnings.count == 1, "Expected 1 warning but got \(warnings.count)")
        #expect(warnings.first?.contains("42984L105") == true)
    }

    @Test("CUSIP without source company buy record generates warning (no target fallback)")
    func cusipWithoutSourceGeneratesWarning() throws {
        // Scenario: No buy record for source company (CAPA), only have sell record for target (QSI)
        // The CUSIP in the Delivered record represents CAPA shares being removed, NOT QSI.
        // We should NOT fallback to target company because:
        // 1. The Delivered record is for CAPA (source), not QSI (target)
        // 2. Creating symbolExchangeIn for QSI would be incorrect
        // 3. We need the CAPA buy record to properly resolve the CUSIP
        let sellQSITransaction = makeTransaction(
            date: "12/30/2021",
            action: "Sell",
            symbol: "QSI",
            description: "QUANTUM-SI INC COM",
            quantity: "-2",
            price: "$5.00",
            amount: "$10.00"
        )
        let deliveredTransaction = makeTransaction(
            date: "06/11/2021",
            action: "Delivered - Other",
            symbol: "42984L105",  // CUSIP - no CAPA buy record to resolve against
            description: "HIGHCAPE CAP ACQUISITION CORP 1:1 R/S 6/1//21 74765K105 1:1 EXCHANGE TO QUANTUM-SI INC 74765K105 Auto Reorg#537627ISTOCK PAYMENT",
            quantity: "-2"
        )
        let data = makeJSONData(transactions: [sellQSITransaction, deliveredTransaction])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        // Should only have 1 trade (the sell), not the exchange
        #expect(trades.count == 1, "Expected 1 trade but got \(trades.count)")
        #expect(trades.first?.type == .stockSell, "Expected stockSell trade")

        // Should have a warning about unresolved CUSIP
        #expect(warnings.count == 1, "Expected 1 warning but got \(warnings.count)")
        #expect(warnings.first?.contains("42984L105") == true, "Warning should mention the CUSIP")
    }

    @Test("Full SPAC exchange flow: buy source, delivered CUSIP, received target, sell target")
    func fullSpacExchangeFlow() throws {
        // This test matches the user's exact scenario:
        // 1. Buy 2 CAPA
        // 2. Delivered -2 (CUSIP) for exchange out
        // 3. Received +2 QSI for exchange in
        // 4. Sell 2 QSI
        // Expected: CAPA net 0, QSI net 0
        let buyCAPA = makeTransaction(
            date: "02/24/2021",
            action: "Buy",
            symbol: "CAPA",
            description: "HIGHCAPE CAP ACQUISITION CORP COM CL A",
            quantity: "2",
            price: "$15.50",
            amount: "-$31.00"
        )
        let deliveredCUSIP = makeTransaction(
            date: "06/11/2021",
            action: "Delivered - Other",
            symbol: "42984L105",
            description: "HIGHCAPE CAP ACQUISITION CORP 1:1 R/S 6/1//21 74765K105 1:1 EXCHANGE TO QUANTUM-SI INC 74765K105 Auto Reorg#537627ISTOCK PAYMENT",
            quantity: "-2"
        )
        let receivedQSI = makeTransaction(
            date: "06/11/2021",
            action: "Received - Other",
            symbol: "QSI",
            description: "QUANTUM-SI INC COM CL A 1:1 EXCHANGE TO QUANTUM-SI INC 74765K105 Auto Reorg#537627ISTOCK PAYMENT",
            quantity: "2"
        )
        let sellQSI = makeTransaction(
            date: "12/30/2021",
            action: "Sell",
            symbol: "QSI",
            description: "TDA TRAN - Sold 2 (QSI) @7.7750",
            quantity: "2",
            price: "$7.775",
            amount: "$15.55"
        )
        let data = makeJSONData(transactions: [buyCAPA, deliveredCUSIP, receivedQSI, sellQSI])

        let (trades, warnings) = try parser.parseWithWarnings(data)

        // Should have no warnings
        #expect(warnings.isEmpty, "Expected no warnings but got: \(warnings)")

        // Should have 4 trades
        #expect(trades.count == 4, "Expected 4 trades but got \(trades.count)")

        // Verify trade types
        let buyTrade = trades.first { $0.type == .stockBuy }
        #expect(buyTrade?.ticker == "CAPA", "Expected CAPA buy")
        #expect(buyTrade?.quantity == 2)

        let exchangeOut = trades.first { $0.type == .symbolExchangeOut }
        #expect(exchangeOut != nil, "Expected symbolExchangeOut for CAPA")
        #expect(exchangeOut?.ticker == "CAPA", "Expected CAPA exchange out but got \(exchangeOut?.ticker ?? "nil")")
        #expect(exchangeOut?.quantity == 2)

        let exchangeIn = trades.first { $0.type == .symbolExchangeIn }
        #expect(exchangeIn != nil, "Expected symbolExchangeIn for QSI")
        #expect(exchangeIn?.ticker == "QSI", "Expected QSI exchange in but got \(exchangeIn?.ticker ?? "nil")")
        #expect(exchangeIn?.quantity == 2)

        let sellTrade = trades.first { $0.type == .stockSell }
        #expect(sellTrade?.ticker == "QSI", "Expected QSI sell")
        #expect(sellTrade?.quantity == 2)

        // Net calculation:
        // CAPA: +2 (buy) -2 (exchange out) = 0
        // QSI: +2 (exchange in) -2 (sell) = 0
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
