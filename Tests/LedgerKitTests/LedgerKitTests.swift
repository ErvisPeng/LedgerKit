import Foundation
import Testing
@testable import LedgerKit

@Suite("LedgerKit Tests")
struct LedgerKitTests {

    @Test("Version is defined")
    func versionIsDefined() {
        #expect(ledgerKitVersion == "0.1.0")
    }

    @Test("SupportedBroker has expected cases")
    func supportedBrokerCases() {
        let brokers = SupportedBroker.allCases
        #expect(brokers.count == 2)
        #expect(brokers.contains(.charlesSchwab))
        #expect(brokers.contains(.firstrade))
    }

    @Test("FileFormat has expected cases")
    func fileFormatCases() {
        let formats = FileFormat.allCases
        #expect(formats.contains(.json))
        #expect(formats.contains(.csv))
        #expect(formats.contains(.xml))
    }

    @Test("ParsedTradeType properties are correct")
    func parsedTradeTypeProperties() {
        #expect(ParsedTradeType.stockBuy.isBuy == true)
        #expect(ParsedTradeType.stockBuy.isSell == false)
        #expect(ParsedTradeType.stockSell.isBuy == false)
        #expect(ParsedTradeType.stockSell.isSell == true)
        #expect(ParsedTradeType.optionBuyToOpen.isOption == true)
        #expect(ParsedTradeType.stockBuy.isOption == false)
    }

    @Test("OptionType has expected values")
    func optionTypeValues() {
        #expect(OptionType.call.rawValue == "C")
        #expect(OptionType.put.rawValue == "P")
        #expect(OptionType.call.displayName == "Call")
        #expect(OptionType.put.displayName == "Put")
    }

    @Test("ParsedOptionInfo generates correct Yahoo symbol")
    func optionInfoYahooSymbol() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2025, month: 12, day: 19)
        let expirationDate = calendar.date(from: components)!

        let optionInfo = ParsedOptionInfo(
            underlyingTicker: "AAPL",
            optionType: .call,
            strikePrice: 150.0,
            expirationDate: expirationDate
        )

        #expect(optionInfo.yahooSymbol == "AAPL251219C00150000")
    }

    @Test("BrokerParserFactory creates correct parsers")
    func brokerParserFactoryCreatesCorrectParsers() {
        let schwabParser = BrokerParserFactory.parser(for: .charlesSchwab)
        let firstradeParser = BrokerParserFactory.parser(for: .firstrade)

        #expect(type(of: schwabParser) == CharlesSchwabParser.self)
        #expect(type(of: firstradeParser) == FirstradeParser.self)
    }
}
