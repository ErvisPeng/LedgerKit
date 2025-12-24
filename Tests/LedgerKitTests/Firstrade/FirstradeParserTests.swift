import Foundation
import Testing
@testable import LedgerKit

@Suite("FirstradeParser Tests")
struct FirstradeParserTests {

    // MARK: - Test Data

    private let validCSVHeader = """
        Symbol,Quantity,Price,Action,Description,TradeDate,SettledDate,Interest,Amount,Commission,Fee,CUSIP,RecordType
        """

    private let stockBuyRecord = """
        AAPL,100.00,150.50,BUY,APPLE INC,2025-01-15,2025-01-17,0.00,-15050.00,0.00,0.00,037833100,Trade
        """

    private let stockSellRecord = """
        AAPL,-50.00,155.00,SELL,APPLE INC,2025-01-20,2025-01-22,0.00,7750.00,0.00,0.00,037833100,Trade
        """

    private let optionBuyRecord = """
        ,1.00,5.50,BUY,CALL AAPL   01/17/25    150    APPLE INC                      UNSOLICITED                    OPEN CONTRACT,2025-01-10,2025-01-12,0.00,-550.02,0.00,0.00,,Trade
        """

    private let optionSellRecord = """
        ,-1.00,3.20,SELL,PUT  HIMS   11/07/25    45     HIMS & HERS HEALTH INC CL A    UNSOLICITED                    OPEN CONTRACT,2025-11-05,2025-11-06,0.00,319.98,0.00,0.00,,Trade
        """

    private let dividendRecord = """
        PAGS,0.00,,Dividend,***PAGSEGURO DIGITAL LTD CLASS A COMMON SHARES CASH DIV  ON     100 SHS,2025-11-03,2025-11-03,0.00,12.00,0.00,0.00,G68707101,Financial
        """

    private let otherRecord = """
        ,0.00,,Other,MEMO CASH ADVANCE ATM,2025-11-06,2025-11-06,0.00,-647.21,0.00,0.00,,Financial
        """

    // MARK: - Parser Instance

    private let parser = FirstradeParser()

    // MARK: - Header Validation Tests

    @Test("Valid CSV header is accepted")
    func validHeaderAccepted() throws {
        let csv = "\(validCSVHeader)\n\(stockBuyRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)

        #expect(records.count == 1)
    }

    @Test("Invalid header throws error")
    func invalidHeaderThrows() {
        let csv = "Invalid,Header,Row\nSome,Data,Here"
        let data = csv.data(using: .utf8)!

        #expect(throws: FirstradeParserError.self) {
            _ = try parser.parseCSV(data)
        }
    }

    @Test("Empty data throws error")
    func emptyDataThrows() {
        let data = Data()

        #expect(throws: FirstradeParserError.self) {
            _ = try parser.parseCSV(data)
        }
    }

    // MARK: - Stock Trade Parsing Tests

    @Test("Stock buy record is parsed correctly")
    func stockBuyRecordParsed() throws {
        let csv = "\(validCSVHeader)\n\(stockBuyRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockBuy)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 100)
        #expect(trade.price == Decimal(string: "150.50"))
        #expect(trade.totalAmount == Decimal(string: "15050.00"))
        #expect(trade.optionInfo == nil)
    }

    @Test("Stock sell record is parsed correctly")
    func stockSellRecordParsed() throws {
        let csv = "\(validCSVHeader)\n\(stockSellRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .stockSell)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 50)
        #expect(trade.price == 155)
    }

    // MARK: - Option Trade Parsing Tests

    @Test("Option buy record is parsed correctly")
    func optionBuyRecordParsed() throws {
        let csv = "\(validCSVHeader)\n\(optionBuyRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .optionBuyToOpen)
        #expect(trade.ticker == "AAPL")
        #expect(trade.quantity == 1)
        #expect(trade.price == Decimal(string: "5.50"))
        #expect(trade.optionInfo != nil)
        #expect(trade.optionInfo?.optionType == .call)
        #expect(trade.optionInfo?.strikePrice == 150)
        #expect(trade.optionInfo?.underlyingTicker == "AAPL")
    }

    @Test("Option sell record is parsed correctly")
    func optionSellRecordParsed() throws {
        let csv = "\(validCSVHeader)\n\(optionSellRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .optionSellToOpen)
        #expect(trade.ticker == "HIMS")
        #expect(trade.quantity == 1)
        #expect(trade.optionInfo != nil)
        #expect(trade.optionInfo?.optionType == .put)
        #expect(trade.optionInfo?.strikePrice == 45)
    }

    // MARK: - Dividend Parsing Tests

    @Test("Dividend record is parsed correctly")
    func dividendRecordParsed() throws {
        let csv = "\(validCSVHeader)\n\(dividendRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .dividend)
        #expect(trade.ticker == "PAGS")
        #expect(trade.totalAmount == 12)
        #expect(trade.quantity == 0)
        #expect(trade.price == 0)
        #expect(trade.dividendInfo != nil)
        #expect(trade.dividendInfo?.grossAmount == 12)
        #expect(trade.dividendInfo?.taxWithheld == 0)
    }

    @Test("Dividend with tax withheld is parsed correctly")
    func dividendWithTaxWithheldParsed() throws {
        let dividendWithTaxRecord = """
            KO,0.00,,Dividend,***COCA COLA COMPANY CASH DIV  ON     100 SHS REC DATE 12/01/25 PAY DATE 12/15/25 NON-RES TAX WITHHELD $1.58,2025-12-15,2025-12-15,0.00,9.00,0.00,0.00,191216100,Financial
            """
        let csv = "\(validCSVHeader)\n\(dividendWithTaxRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .dividend)
        #expect(trade.ticker == "KO")
        #expect(trade.totalAmount == 9)
        #expect(trade.dividendInfo != nil)
        #expect(trade.dividendInfo?.grossAmount == Decimal(string: "10.58"))
        #expect(trade.dividendInfo?.taxWithheld == Decimal(string: "1.58"))
        #expect(trade.dividendInfo?.netAmount == 9)
    }

    // MARK: - ADR Fee Parsing Tests

    @Test("ADR Fee is parsed as fee type")
    func adrFeeParsed() throws {
        let adrFeeRecord = """
            ARM,0.00,,Other,***ARM HOLDINGS PLC SPONSORED ADS ADR FEE ON 50 SHS,2025-11-06,2025-11-06,0.00,-1.25,0.00,0.00,042068104,Financial
            """
        let csv = "\(validCSVHeader)\n\(adrFeeRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)

        let trade = trades[0]
        #expect(trade.type == .fee)
        #expect(trade.ticker == "ARM")
        #expect(trade.totalAmount == Decimal(string: "1.25"))
        #expect(trade.feeInfo != nil)
        #expect(trade.feeInfo?.type == .adrMgmtFee)
        #expect(trade.feeInfo?.amount == Decimal(string: "1.25"))
    }

    // MARK: - Non-Trade Record Tests

    @Test("Other financial records are skipped")
    func otherRecordsSkipped() throws {
        let csv = "\(validCSVHeader)\n\(otherRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(records.count == 1)
        // MEMO CASH ADVANCE ATM is now parsed as withdraw
        #expect(trades.count == 1)
        #expect(trades.first?.type == .withdraw)
    }

    // MARK: - Option Description Parsing Tests

    @Test("Call option description is parsed correctly")
    func callOptionDescriptionParsed() {
        let description = "CALL AAPL   01/17/25    150    APPLE INC"
        let optionInfo = parser.parseOptionDescription(description)

        #expect(optionInfo != nil)
        #expect(optionInfo?.optionType == .call)
        #expect(optionInfo?.underlyingTicker == "AAPL")
        #expect(optionInfo?.strikePrice == 150)
    }

    @Test("Put option description is parsed correctly")
    func putOptionDescriptionParsed() {
        let description = "PUT  HIMS   11/07/25    45     HIMS & HERS HEALTH INC CL A"
        let optionInfo = parser.parseOptionDescription(description)

        #expect(optionInfo != nil)
        #expect(optionInfo?.optionType == .put)
        #expect(optionInfo?.underlyingTicker == "HIMS")
        #expect(optionInfo?.strikePrice == 45)
    }

    @Test("Option description with decimal strike price is parsed")
    func decimalStrikePriceParsed() {
        let description = "CALL LUMN   01/16/26     5.50  LUMEN TECHNOLOGIES INC"
        let optionInfo = parser.parseOptionDescription(description)

        #expect(optionInfo != nil)
        #expect(optionInfo?.strikePrice == Decimal(string: "5.50"))
    }

    @Test("Invalid option description returns nil")
    func invalidOptionDescriptionReturnsNil() {
        let description = "APPLE INC COMMON STOCK"
        let optionInfo = parser.parseOptionDescription(description)

        #expect(optionInfo == nil)
    }

    // MARK: - Mixed Records Tests

    @Test("Multiple record types are parsed correctly")
    func multipleRecordTypesParsed() throws {
        let csv = """
            \(validCSVHeader)
            \(stockBuyRecord)
            \(optionSellRecord)
            \(dividendRecord)
            \(otherRecord)
            """
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(records.count == 4)
        // otherRecord (MEMO CASH ADVANCE ATM) is now parsed as withdraw
        #expect(trades.count == 4)

        // Trades should be sorted by date
        let types = trades.map { $0.type }
        #expect(types.contains(.stockBuy))
        #expect(types.contains(.optionSellToOpen))
        #expect(types.contains(.dividend))
        #expect(types.contains(.withdraw))
    }

    // MARK: - Date Parsing Tests

    @Test("Trade date is parsed correctly")
    func tradeDateParsed() throws {
        let csv = "\(validCSVHeader)\n\(stockBuyRecord)"
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)

        #expect(records.count == 1)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: records[0].tradeDate)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test("Option expiration date is parsed correctly")
    func optionExpirationDateParsed() {
        let description = "PUT  HIMS   11/07/25    45     HIMS"
        let optionInfo = parser.parseOptionDescription(description)

        #expect(optionInfo != nil)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: optionInfo!.expirationDate)
        #expect(components.month == 11)
        #expect(components.day == 7)
        #expect(components.year == 2025)
    }

    // MARK: - ParsedTradeType Properties Tests

    @Test("ParsedTradeType isBuy property")
    func parsedTradeTypeIsBuy() {
        #expect(ParsedTradeType.stockBuy.isBuy == true)
        #expect(ParsedTradeType.optionBuyToOpen.isBuy == true)
        #expect(ParsedTradeType.stockSell.isBuy == false)
        #expect(ParsedTradeType.optionSellToOpen.isBuy == false)
        #expect(ParsedTradeType.dividend.isBuy == false)
    }

    @Test("ParsedTradeType isSell property")
    func parsedTradeTypeIsSell() {
        #expect(ParsedTradeType.stockSell.isSell == true)
        #expect(ParsedTradeType.optionSellToOpen.isSell == true)
        #expect(ParsedTradeType.stockBuy.isSell == false)
        #expect(ParsedTradeType.optionBuyToOpen.isSell == false)
        #expect(ParsedTradeType.dividend.isSell == false)
    }

    @Test("ParsedTradeType isOption property")
    func parsedTradeTypeIsOption() {
        #expect(ParsedTradeType.optionBuyToOpen.isOption == true)
        #expect(ParsedTradeType.optionSellToOpen.isOption == true)
        #expect(ParsedTradeType.stockBuy.isOption == false)
        #expect(ParsedTradeType.stockSell.isOption == false)
        #expect(ParsedTradeType.dividend.isOption == false)
    }

    // MARK: - BrokerParser Protocol Tests

    @Test("Parser conforms to BrokerParser protocol")
    func parserConformsToBrokerParser() {
        #expect(FirstradeParser.brokerName == "Firstrade")
        #expect(FirstradeParser.supportedFormats == [.csv])
    }

    @Test("Parse method returns trades")
    func parseMethodReturnsTrades() throws {
        let csv = "\(validCSVHeader)\n\(stockBuyRecord)"
        let data = csv.data(using: .utf8)!

        let trades = try parser.parse(data)

        #expect(trades.count == 1)
        #expect(trades[0].type == .stockBuy)
    }

    @Test("ParseWithWarnings method returns trades and warnings")
    func parseWithWarningsMethodReturnsTrades() throws {
        let csv = "\(validCSVHeader)\n\(stockBuyRecord)"
        let data = csv.data(using: .utf8)!

        let (trades, warnings) = try parser.parseWithWarnings(data)

        #expect(trades.count == 1)
        #expect(warnings.isEmpty)
    }

    // MARK: - Dividend with Tax Withholding Tests

    @Test("Dividend reinvestment with tax withholding is parsed correctly")
    func dividendReinvestmentWithTaxParsed() throws {
        let csv = """
            \(validCSVHeader)
            KO          ,0.05252,,Other,COCA COLA COMPANY (THE) REIN @  70.8300 REC 12/01/25 PAY 12/15/25 FLEET MEEHAN SPECIALIST IS A SPECIALIST IN THIS STOCK  ,2025-12-15,2025-12-15,0.00,-3.72,0.00,0.00,191216100,Financial
            KO          ,0.00,,Dividend,COCA COLA COMPANY (THE) SUBST PAY ON       9 SHS REC 12/01/25 PAY 12/15/25 IN LIEU OF DIVIDEND NON-RES TAX WITHHELD  $1.38,2025-12-15,2025-12-15,0.00,4.59,0.00,0.00,191216100,Financial
            KO          ,0.00,,Dividend,COCA COLA COMPANY (THE) CASH DIV  ON 1.42524 SHS REC 12/01/25 PAY 12/15/25 NON-RES TAX WITHHELD  $0.22,2025-12-15,2025-12-15,0.00,0.73,0.00,0.00,191216100,Financial
            """
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        // Should parse 3 trades: 1 dividendReinvest + 2 dividends
        #expect(trades.count == 3)

        // First trade: Dividend Reinvestment (REIN)
        let reinvest = trades[0]
        #expect(reinvest.type == .dividendReinvest)
        #expect(reinvest.ticker == "KO")
        #expect(reinvest.quantity == Decimal(string: "0.05252"))
        #expect(reinvest.price == Decimal(string: "70.8300"))
        #expect(reinvest.totalAmount == Decimal(string: "3.72"))

        // Second trade: SUBST PAY dividend
        let substPay = trades[1]
        #expect(substPay.type == .dividend)
        #expect(substPay.ticker == "KO")
        #expect(substPay.dividendInfo != nil)
        #expect(substPay.dividendInfo?.taxWithheld == Decimal(string: "1.38"))
        #expect(substPay.dividendInfo?.netAmount == Decimal(string: "4.59"))
        #expect(substPay.dividendInfo?.grossAmount == Decimal(string: "5.97"))  // 4.59 + 1.38

        // Third trade: CASH DIV dividend
        let cashDiv = trades[2]
        #expect(cashDiv.type == .dividend)
        #expect(cashDiv.ticker == "KO")
        #expect(cashDiv.dividendInfo != nil)
        #expect(cashDiv.dividendInfo?.taxWithheld == Decimal(string: "0.22"))
        #expect(cashDiv.dividendInfo?.netAmount == Decimal(string: "0.73"))
        #expect(cashDiv.dividendInfo?.grossAmount == Decimal(string: "0.95"))  // 0.73 + 0.22
    }

    // MARK: - Interest Parsing Tests

    @Test("Credit interest on cash balance is parsed correctly")
    func creditInterestParsed() throws {
        let csv = """
            \(validCSVHeader)
            ,0.00,,Interest,INTEREST ON CREDIT BALANCE AT  0.450  06/16 THRU 07/15      ,2023-07-17,2023-07-17,0.00,1.4,0.00,0.00,00099A109,Financial
            """
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)
        #expect(trades[0].type == .interestIncome)
        #expect(trades[0].ticker == "")
        #expect(trades[0].totalAmount == Decimal(string: "1.4"))
        #expect(trades[0].note.contains("INTEREST ON CREDIT BALANCE"))
    }

    @Test("Securities lending rebate is parsed correctly")
    func securitiesLendingRebateParsed() throws {
        let csv = """
            \(validCSVHeader)
            ,0.00,,Interest,FULLYPAID LENDING REBATE Apr2024 REBATE NON-RES TAX WITHHELD DUE 12/31/2035      0.000    $0.14,2024-05-13,2024-05-13,0.00,0.46,0.00,0.00,         ,Financial
            """
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)
        #expect(trades[0].type == .interestIncome)
        #expect(trades[0].ticker == "")
        #expect(trades[0].totalAmount == Decimal(string: "0.46"))
        #expect(trades[0].note.contains("LENDING REBATE"))
    }

    @Test("Margin interest expense is parsed correctly")
    func marginInterestParsed() throws {
        let csv = """
            \(validCSVHeader)
            ,0.00,,Interest,FROM 08/16 THRU 09/15 @13 3/4 BAL       10-  AVBAL      512      ,2024-09-16,2024-09-16,0.00,-6.06,0.00,0.00,         ,Financial
            """
        let data = csv.data(using: .utf8)!

        let records = try parser.parseCSV(data)
        let trades = parser.extractTrades(from: records)

        #expect(trades.count == 1)
        #expect(trades[0].type == .marginInterest)
        #expect(trades[0].ticker == "")
        #expect(trades[0].totalAmount == Decimal(string: "-6.06"))
    }
}
