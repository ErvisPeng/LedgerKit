import Foundation

// MARK: - FirstradeParser

/// Parser for Firstrade CSV transaction exports.
///
/// Firstrade provides transaction history as CSV files. This parser
/// converts those files into the unified `ParsedTrade` format.
///
/// Example:
/// ```swift
/// let parser = FirstradeParser()
/// let trades = try parser.parse(csvData)
/// ```
public final class FirstradeParser: BrokerParser, Sendable {

    // MARK: - BrokerParser Conformance

    public static let brokerName = "Firstrade"
    public static let supportedFormats: [FileFormat] = [.csv]

    // MARK: - Expected CSV Header

    /// Expected CSV header columns (fixed order)
    private static let expectedHeaders = [
        "Symbol", "Quantity", "Price", "Action", "Description",
        "TradeDate", "SettledDate", "Interest", "Amount",
        "Commission", "Fee", "CUSIP", "RecordType"
    ]

    // MARK: - Date Formatters

    /// Firstrade date format: YYYY-MM-DD
    private static let tradeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Option expiration date format: MM/DD/YY
    private static let optionExpirationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Initialization

    public init() {}

    // MARK: - BrokerParser Implementation

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        let records = try parseCSV(data)
        let trades = extractTrades(from: records)
        return (trades, [])
    }

    // MARK: - Public Methods

    /// Parse CSV data into raw records.
    /// - Parameter data: CSV file data
    /// - Returns: Array of parsed raw records
    public func parseCSV(_ data: Data) throws -> [FirstradeCSVRecord] {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw FirstradeParserError.invalidData
        }

        let lines = csvString.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else {
            throw FirstradeParserError.invalidData
        }

        // Validate header
        let headerLine = lines[0]
        try validateHeader(headerLine)

        // Parse data rows
        var records: [FirstradeCSVRecord] = []
        for lineIndex in 1..<lines.count {
            let line = lines[lineIndex]
            if let record = try? parseCSVLine(line) {
                records.append(record)
            }
        }

        return records
    }

    /// Convert raw records to parsed trades.
    /// - Parameter records: Raw CSV records
    /// - Returns: Array of parsed trades
    public func extractTrades(from records: [FirstradeCSVRecord]) -> [ParsedTrade] {
        var trades: [ParsedTrade] = []

        for record in records {
            if let trade = parseTrade(from: record) {
                trades.append(trade)
            }
        }

        // Sort by trade date (oldest first), buys before sells on same day
        return trades.sorted { trade1, trade2 in
            if trade1.tradeDate != trade2.tradeDate {
                return trade1.tradeDate < trade2.tradeDate
            }
            // Same day: buys before sells, sells before dividends
            let priority1 = trade1.type.isBuy ? 0 : (trade1.type.isSell ? 1 : 2)
            let priority2 = trade2.type.isBuy ? 0 : (trade2.type.isSell ? 1 : 2)
            return priority1 < priority2
        }
    }

    // MARK: - Private Methods

    /// Validate CSV header
    private func validateHeader(_ headerLine: String) throws {
        let headers = parseCSVFields(headerLine)
        let expectedHeaders = Self.expectedHeaders

        // Check header count and content
        guard headers.count >= expectedHeaders.count else {
            throw FirstradeParserError.invalidHeader
        }

        for (index, expected) in expectedHeaders.enumerated() {
            if headers[index].trimmingCharacters(in: .whitespaces) != expected {
                throw FirstradeParserError.invalidHeader
            }
        }
    }

    /// Parse single CSV line
    private func parseCSVLine(_ line: String) throws -> FirstradeCSVRecord {
        let fields = parseCSVFields(line)

        guard fields.count >= 13 else {
            throw FirstradeParserError.parsingFailed("Insufficient fields")
        }

        let symbol = fields[0].trimmingCharacters(in: .whitespaces)
        let quantity = Decimal(string: fields[1].trimmingCharacters(in: .whitespaces)) ?? .zero
        let price = Decimal(string: fields[2].trimmingCharacters(in: .whitespaces)) ?? .zero
        let action = fields[3].trimmingCharacters(in: .whitespaces)
        let description = fields[4].trimmingCharacters(in: .whitespaces)
        let tradeDateStr = fields[5].trimmingCharacters(in: .whitespaces)
        let settledDateStr = fields[6].trimmingCharacters(in: .whitespaces)
        let interest = Decimal(string: fields[7].trimmingCharacters(in: .whitespaces)) ?? .zero
        let amount = Decimal(string: fields[8].trimmingCharacters(in: .whitespaces)) ?? .zero
        let commission = Decimal(string: fields[9].trimmingCharacters(in: .whitespaces)) ?? .zero
        let fee = Decimal(string: fields[10].trimmingCharacters(in: .whitespaces)) ?? .zero
        let cusip = fields[11].trimmingCharacters(in: .whitespaces)
        let recordType = fields[12].trimmingCharacters(in: .whitespaces)

        guard let tradeDate = Self.tradeDateFormatter.date(from: tradeDateStr) else {
            throw FirstradeParserError.invalidDateFormat(tradeDateStr)
        }

        let settledDate = Self.tradeDateFormatter.date(from: settledDateStr) ?? tradeDate

        return FirstradeCSVRecord(
            symbol: symbol,
            quantity: quantity,
            price: price,
            action: action,
            description: description,
            tradeDate: tradeDate,
            settledDate: settledDate,
            interest: interest,
            amount: amount,
            commission: commission,
            fee: fee,
            cusip: cusip,
            recordType: recordType
        )
    }

    /// Parse CSV fields (handle commas and quotes)
    private func parseCSVFields(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)

        return fields
    }

    /// Parse trade from raw record
    private func parseTrade(from record: FirstradeCSVRecord) -> ParsedTrade? {
        let actionUpper = record.action.uppercased()
        let descriptionUpper = record.description.uppercased()

        // 1. ADR Fee
        // Format: Action=Other, RecordType=Financial, Description contains "ADR FEE"
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           descriptionUpper.contains("ADR FEE") {
            return parseADRFee(record)
        }

        // 2. Cash Flow - Deposits
        // Format: Action=Other, RecordType=Financial, Description contains deposit keywords
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           (descriptionUpper.contains("ACH DEPOSIT") ||
            descriptionUpper.contains("WIRE FUNDS RECEIVED")) {
            // Skip reverse deposits (they are withdrawals)
            if !descriptionUpper.contains("REVERSE") {
                return parseDeposit(record)
            }
        }

        // 3. Cash Flow - Withdrawals
        // Format: Action=Other, RecordType=Financial, Description contains withdrawal keywords
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           (descriptionUpper.contains("WIRE TRANSFER") ||
            descriptionUpper.contains("REVERSE ACH DEPOSIT") ||
            descriptionUpper.contains("CASH ADVANCE ATM") ||
            descriptionUpper.contains("MEMO CASH ADVANCE")) {
            return parseWithdraw(record)
        }

        // 3.5. Skip internal transfers (do not affect total assets)
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           (descriptionUpper.contains("XFER MARGIN TO CASH") ||
            descriptionUpper.contains("XFER CASH TO MARGIN")) {
            return nil  // Ignore internal transfers
        }

        // 4. Fee Reimbursements and Rebates (positive amounts -> deposit)
        // Format: Action=Other, RecordType=Financial, Description contains REIMB or REBATE
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           (descriptionUpper.contains("REIMB") || descriptionUpper.contains("REBATE")) {
            // Fee reimbursements are income, treat as deposits
            if record.amount > .zero {
                return parseDeposit(record)
            }
        }

        // 5. Other Fees (Wire fees, ACH fees, Foreign transaction fees)
        // Format: Action=Other, RecordType=Financial, Description contains FEE
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           descriptionUpper.contains("FEE") {
            // Skip ADR fees (already handled above)
            if !descriptionUpper.contains("ADR FEE") {
                return parseOtherFee(record)
            }
        }

        // 5. Dividend records
        if record.recordType == "Financial" && actionUpper == "DIVIDEND" {
            return parseDividend(record)
        }

        // 3. Dividend Reinvestment (DRIP)
        // Format: Action=Other, RecordType=Financial, Description contains "REIN @"
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           descriptionUpper.contains("REIN @") {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return nil }
            guard record.quantity > .zero else { return nil }

            // Parse reinvestment price from description
            let price = parseReinvestmentPrice(record.description) ?? .zero

            return ParsedTrade(
                type: .dividendReinvest,
                ticker: symbol,
                quantity: record.quantity,
                price: price,
                totalAmount: abs(record.amount),
                tradeDate: record.tradeDate,
                optionInfo: nil,
                dividendInfo: nil,
                feeInfo: nil,
                note: record.description,
                rawSource: "Firstrade"
            )
        }

        // 4. Option Expiration
        // Format: Action=Other, RecordType=Financial, Description contains "EXPIRED"
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           descriptionUpper.contains("EXPIRED") {
            guard let optionInfo = parseOptionDescription(record.description) else {
                return nil
            }
            guard record.quantity > .zero else { return nil }

            return ParsedTrade(
                type: .optionExpiration,
                ticker: optionInfo.underlyingTicker,
                quantity: record.quantity,
                price: .zero,
                totalAmount: .zero,
                tradeDate: record.tradeDate,
                optionInfo: optionInfo,
                dividendInfo: nil,
                feeInfo: nil,
                note: record.description,
                rawSource: "Firstrade"
            )
        }

        // 5. Option Assignment
        // Format: Action=Other, RecordType=Financial, Description contains "ASSIGNED"
        if record.recordType == "Financial" && actionUpper == "OTHER" &&
           descriptionUpper.contains("ASSIGNED") {
            guard let optionInfo = parseOptionDescription(record.description) else {
                return nil
            }
            guard record.quantity > .zero else { return nil }

            return ParsedTrade(
                type: .optionAssignment,
                ticker: optionInfo.underlyingTicker,
                quantity: record.quantity,
                price: .zero,
                totalAmount: .zero,
                tradeDate: record.tradeDate,
                optionInfo: optionInfo,
                dividendInfo: nil,
                feeInfo: nil,
                note: record.description,
                rawSource: "Firstrade"
            )
        }

        // 6. Trade records
        guard record.recordType == "Trade" else { return nil }
        guard actionUpper == "BUY" || actionUpper == "SELL" else { return nil }

        // Check if option trade
        let isOption = descriptionUpper.hasPrefix("PUT ") ||
                       descriptionUpper.hasPrefix("CALL ") ||
                       descriptionUpper.hasPrefix("PUT  ") ||
                       descriptionUpper.hasPrefix("CALL ")

        if isOption {
            // Option trade
            guard let optionInfo = parseOptionDescription(record.description) else {
                return nil
            }

            // Determine open/close
            let isOpenContract = descriptionUpper.contains("OPEN CONTRACT")
            let isClosingContract = descriptionUpper.contains("CLOSING CONTRACT")
            let isBuy = actionUpper == "BUY"

            let type: ParsedTradeType
            if isBuy {
                type = isClosingContract ? .optionBuyToClose : .optionBuyToOpen
            } else {
                type = isOpenContract ? .optionSellToOpen : .optionSellToClose
            }

            return ParsedTrade(
                type: type,
                ticker: optionInfo.underlyingTicker,
                quantity: abs(record.quantity),
                price: record.price,
                totalAmount: abs(record.amount),
                tradeDate: record.tradeDate,
                optionInfo: optionInfo,
                dividendInfo: nil,
                feeInfo: nil,
                note: record.description,
                rawSource: "Firstrade"
            )
        } else {
            // Stock trade
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return nil }

            let isBuy = actionUpper == "BUY"
            let type: ParsedTradeType = isBuy ? .stockBuy : .stockSell

            return ParsedTrade(
                type: type,
                ticker: symbol,
                quantity: abs(record.quantity),
                price: record.price,
                totalAmount: abs(record.amount),
                tradeDate: record.tradeDate,
                optionInfo: nil,
                dividendInfo: nil,
                feeInfo: nil,
                note: record.description,
                rawSource: "Firstrade"
            )
        }
    }

    // MARK: - Dividend Parsing

    /// Parse dividend record with tax withholding from description.
    private func parseDividend(_ record: FirstradeCSVRecord) -> ParsedTrade? {
        let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }

        // Amount is net amount (after tax)
        let netAmount = abs(record.amount)
        guard netAmount > .zero else { return nil }

        // Parse tax withheld from description
        // Example: "...NON-RES TAX WITHHELD $1.58"
        let taxWithheld = parseTaxWithheld(from: record.description) ?? .zero
        let grossAmount = netAmount + taxWithheld

        let dividendInfo = DividendInfo(
            type: .ordinary,  // Firstrade doesn't distinguish qualified/ordinary
            grossAmount: grossAmount,
            taxWithheld: taxWithheld,
            issueId: nil
        )

        return ParsedTrade(
            type: .dividend,
            ticker: symbol,
            quantity: .zero,
            price: .zero,
            totalAmount: netAmount,
            tradeDate: record.tradeDate,
            optionInfo: nil,
            dividendInfo: dividendInfo,
            feeInfo: nil,
            note: record.description,
            rawSource: "Firstrade"
        )
    }

    /// Parse tax withheld from description.
    /// Example: "NON-RES TAX WITHHELD $1.58" → 1.58
    private func parseTaxWithheld(from description: String) -> Decimal? {
        let pattern = #"NON-RES TAX WITHHELD\s+\$?([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: description,
                  range: NSRange(description.startIndex..., in: description)
              ),
              let range = Range(match.range(at: 1), in: description) else {
            return nil
        }
        return Decimal(string: String(description[range]))
    }

    // MARK: - ADR Fee Parsing

    /// Parse ADR Management Fee record.
    private func parseADRFee(_ record: FirstradeCSVRecord) -> ParsedTrade? {
        let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }

        let amount = abs(record.amount)
        guard amount > .zero else { return nil }

        let feeInfo = FeeInfo(
            type: .adrMgmtFee,
            amount: amount
        )

        return ParsedTrade(
            type: .fee,
            ticker: symbol,
            quantity: .zero,
            price: .zero,
            totalAmount: amount,
            tradeDate: record.tradeDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: feeInfo,
            note: record.description,
            rawSource: "Firstrade"
        )
    }

    // MARK: - Cash Flow Parsing

    /// Parse deposit record (ACH deposit, wire transfer received).
    private func parseDeposit(_ record: FirstradeCSVRecord) -> ParsedTrade? {
        let amount = abs(record.amount)
        guard amount > .zero else { return nil }

        return ParsedTrade(
            type: .deposit,
            ticker: "",  // No ticker for cash deposits
            quantity: .zero,
            price: .zero,
            totalAmount: amount,
            tradeDate: record.tradeDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: nil,
            note: record.description,
            rawSource: "Firstrade"
        )
    }

    /// Parse withdrawal record (wire transfer, reverse ACH deposit).
    private func parseWithdraw(_ record: FirstradeCSVRecord) -> ParsedTrade? {
        let amount = abs(record.amount)
        guard amount > .zero else { return nil }

        return ParsedTrade(
            type: .withdraw,
            ticker: "",  // No ticker for cash withdrawals
            quantity: .zero,
            price: .zero,
            totalAmount: amount,
            tradeDate: record.tradeDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: nil,
            note: record.description,
            rawSource: "Firstrade"
        )
    }

    /// Parse other fee record (wire fee, ACH fee, rebates).
    private func parseOtherFee(_ record: FirstradeCSVRecord) -> ParsedTrade? {
        let amount = abs(record.amount)
        guard amount > .zero else { return nil }

        // Determine fee type from description
        let descUpper = record.description.uppercased()
        let feeType: FeeType
        if descUpper.contains("FOREIGN") && (descUpper.contains("TRANSACTION") || descUpper.contains("CARD")) {
            // Foreign transaction fee (ATM, debit card, etc.)
            feeType = .foreignTransactionFee
        } else if descUpper.contains("WIRE") {
            feeType = .wireFee
        } else if descUpper.contains("ACH") {
            feeType = .achFee
        } else if descUpper.contains("REBATE") {
            feeType = .other
        } else {
            feeType = .other
        }

        let feeInfo = FeeInfo(
            type: feeType,
            amount: amount
        )

        return ParsedTrade(
            type: .fee,
            ticker: "",  // No ticker for fees
            quantity: .zero,
            price: .zero,
            totalAmount: amount,
            tradeDate: record.tradeDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: feeInfo,
            note: record.description,
            rawSource: "Firstrade"
        )
    }

    // MARK: - Option Parsing

    /// Parse option description.
    /// Format: {PUT/CALL} {TICKER} {MM/DD/YY} {STRIKE} {DESCRIPTION}...
    /// Example: PUT  HIMS   11/07/25    45     HIMS & HERS HEALTH INC CL A
    public func parseOptionDescription(_ description: String) -> ParsedOptionInfo? {
        let trimmed = description.trimmingCharacters(in: .whitespaces)

        // Use regex to parse
        // Format: (PUT|CALL)\s+(\w+)\s+(\d{2}/\d{2}/\d{2})\s+([\d.]+)
        let pattern = #"^(PUT|CALL)\s+([A-Z]+)\s+(\d{2}/\d{2}/\d{2})\s+([\d.]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: trimmed,
                  options: [],
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              )
        else {
            return nil
        }

        // Extract match groups
        guard let optionTypeRange = Range(match.range(at: 1), in: trimmed),
              let tickerRange = Range(match.range(at: 2), in: trimmed),
              let dateRange = Range(match.range(at: 3), in: trimmed),
              let strikeRange = Range(match.range(at: 4), in: trimmed)
        else {
            return nil
        }

        let optionTypeStr = String(trimmed[optionTypeRange]).uppercased()
        let ticker = String(trimmed[tickerRange]).uppercased()
        let dateStr = String(trimmed[dateRange])
        let strikeStr = String(trimmed[strikeRange])

        // Parse option type
        let optionType: OptionType
        switch optionTypeStr {
        case "PUT":
            optionType = .put
        case "CALL":
            optionType = .call
        default:
            return nil
        }

        // Parse expiration date
        guard let expirationDate = Self.optionExpirationFormatter.date(from: dateStr) else {
            return nil
        }

        // Parse strike price
        guard let strikePrice = Decimal(string: strikeStr) else {
            return nil
        }

        return ParsedOptionInfo(
            underlyingTicker: ticker,
            optionType: optionType,
            strikePrice: strikePrice,
            expirationDate: expirationDate
        )
    }

    /// Parse dividend reinvestment price.
    /// Format: ... REIN @ 158.8300 ...
    private func parseReinvestmentPrice(_ description: String) -> Decimal? {
        let pattern = #"REIN\s*@\s*([\d.]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: description,
                  options: [],
                  range: NSRange(description.startIndex..., in: description)
              ),
              let priceRange = Range(match.range(at: 1), in: description)
        else {
            return nil
        }

        let priceStr = String(description[priceRange])
        return Decimal(string: priceStr)
    }
}

// MARK: - Decimal Absolute Value Extension

private extension Decimal {
    func abs() -> Decimal {
        return self < .zero ? -self : self
    }
}

private func abs(_ value: Decimal) -> Decimal {
    return value < .zero ? -value : value
}
