import Foundation

// MARK: - CharlesSchwabParser

/// Parser for Charles Schwab JSON transaction exports.
///
/// Charles Schwab provides transaction history as JSON files. This parser
/// converts those files into the unified `ParsedTrade` format.
///
/// Example:
/// ```swift
/// let parser = CharlesSchwabParser()
/// let trades = try parser.parse(jsonData)
/// ```
public final class CharlesSchwabParser: BrokerParser, Sendable {

    // MARK: - BrokerParser Conformance

    public static let brokerName = "Charles Schwab"
    public static let supportedFormats: [FileFormat] = [.json]

    // MARK: - Date Formatters

    /// CS date format: MM/DD/YYYY
    private static let tradeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Option expiration date format (in CS Symbol): MM/DD/YYYY
    private static let optionExpirationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Initialization

    public init() {}

    // MARK: - BrokerParser Implementation

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        let records = try parseJSON(data)
        let (trades, warnings) = extractTrades(from: records)
        return (trades, warnings)
    }

    // MARK: - Public Methods

    /// Parse JSON data into raw records.
    /// - Parameter data: JSON file data
    /// - Returns: Array of parsed raw records
    public func parseJSON(_ data: Data) throws -> [CharlesSchwabRawTransaction] {
        do {
            let decoder = JSONDecoder()
            let file = try decoder.decode(CharlesSchwabTransactionFile.self, from: data)
            return file.brokerageTransactions
        } catch let decodingError as DecodingError {
            throw CharlesSchwabParserError.invalidJSON(decodingError.localizedDescription)
        } catch {
            throw CharlesSchwabParserError.invalidData
        }
    }

    /// Convert raw records to parsed trades.
    /// - Parameter records: Raw JSON records
    /// - Returns: Tuple of parsed trades and warning messages
    public func extractTrades(
        from records: [CharlesSchwabRawTransaction]
    ) -> ([ParsedTrade], [String]) {
        var trades: [ParsedTrade] = []
        let warnings: [String] = []

        // Build company name to ticker mapping for CUSIP resolution
        let companyTickerMap = buildCompanyTickerMap(from: records)

        // Group records by ItemIssueId for dividend + tax merging
        let grouped = Dictionary(grouping: records) { $0.itemIssueId }

        for (issueId, group) in grouped {
            // Non-empty issueId: try to merge dividend + tax
            if !issueId.isEmpty && issueId != "0" {
                if let mergedTrade = tryMergeDividendWithTax(group, issueId: issueId) {
                    trades.append(mergedTrade)
                    continue
                }
            }

            // Process each record individually
            for record in group {
                if let trade = parseTrade(from: record, companyTickerMap: companyTickerMap) {
                    trades.append(trade)
                }
            }
        }

        // Sort by trade date (oldest first), buys before sells on same day
        let sortedTrades = trades.sorted { trade1, trade2 in
            if trade1.tradeDate != trade2.tradeDate {
                return trade1.tradeDate < trade2.tradeDate
            }
            // Same day: buys before sells, sells before dividends
            let priority1 = trade1.type.isBuy ? 0 : (trade1.type.isSell ? 1 : 2)
            let priority2 = trade2.type.isBuy ? 0 : (trade2.type.isSell ? 1 : 2)
            return priority1 < priority2
        }
        return (sortedTrades, warnings)
    }

    // MARK: - Dividend + Tax Merging

    /// Try to merge dividend and NRA Tax Adj records with same ItemIssueId.
    private func tryMergeDividendWithTax(
        _ records: [CharlesSchwabRawTransaction],
        issueId: String
    ) -> ParsedTrade? {
        // Find dividend record
        let dividendRecord = records.first { record in
            guard let actionType = CharlesSchwabActionType(rawAction: record.action) else {
                return false
            }
            return actionType.isDividend
        }

        // Find tax record
        let taxRecord = records.first { $0.action == "NRA Tax Adj" }

        guard let dividend = dividendRecord,
              let parsedDate = parseDate(dividend.date) else {
            return nil
        }

        let symbol = dividend.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }

        let grossAmount = abs(parseAmount(dividend.amount))
        guard grossAmount > .zero else { return nil }

        let taxAmount: Decimal
        if let tax = taxRecord {
            taxAmount = abs(parseAmount(tax.amount))
        } else {
            taxAmount = .zero
        }

        // Determine dividend type
        let dividendType: DividendType
        switch dividend.action {
        case "Qualified Dividend":
            dividendType = .qualified
        case "Long Term Cap Gain":
            dividendType = .capitalGain
        default:
            dividendType = .ordinary
        }

        let dividendInfo = DividendInfo(
            type: dividendType,
            grossAmount: grossAmount,
            taxWithheld: taxAmount,
            issueId: issueId
        )

        return ParsedTrade(
            type: .dividend,
            ticker: symbol.uppercased(),
            quantity: .zero,
            price: .zero,
            totalAmount: dividendInfo.netAmount,
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: dividendInfo,
            feeInfo: nil,
            note: "\(dividend.action): \(dividend.description)",
            rawSource: "Charles Schwab"
        )
    }

    // MARK: - CUSIP Detection

    /// Check if symbol is a CUSIP (rather than a ticker).
    /// CUSIP format: 9 alphanumeric characters, usually contains numbers.
    /// Ticker format: 1-5 uppercase letters.
    private func isCUSIP(_ symbol: String) -> Bool {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)

        // Empty string is not CUSIP
        guard !trimmed.isEmpty else { return false }

        // All numeric is definitely CUSIP
        if trimmed.allSatisfy({ $0.isNumber }) {
            return true
        }

        // Length > 5 and contains numbers is likely CUSIP (e.g., 42984L105)
        // Normal tickers are at most 5 letters (e.g., GOOGL)
        if trimmed.count > 5 && trimmed.contains(where: { $0.isNumber }) {
            return true
        }

        return false
    }

    /// Build company name to ticker mapping.
    /// Extracts company names from records with valid tickers.
    private func buildCompanyTickerMap(
        from records: [CharlesSchwabRawTransaction]
    ) -> [String: String] {
        var map: [String: String] = [:]

        for record in records {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)

            // Skip empty or CUSIP symbols
            guard !symbol.isEmpty, !isCUSIP(symbol) else {
                continue
            }

            // Extract company name (first few words until specific keywords)
            if let companyName = extractCompanyName(from: record.description) {
                // Keep first found ticker (usually buy records)
                if map[companyName] == nil {
                    map[companyName] = symbol.uppercased()
                }
            }
        }

        return map
    }

    /// Extract company name from description.
    /// Example: "CHURCHILL CAPITAL CORP IV COM CL A" -> "CHURCHILL CAPITAL CORP IV"
    private func extractCompanyName(from description: String) -> String? {
        let desc = description.uppercased()

        // Common suffixes to truncate at
        let suffixes = [
            " COM CL A", " COM CL B", " COM CL C",
            " COM CLASS A", " COM CLASS B",
            " COMMON", " COM ", " CL A", " CL B",
            " 1:1 EXC", " 1:1 EXCHANGE",
            " INC ", " CORP ", " LTD ", " LLC ",
            " AUTO REORG"
        ]

        var companyName = desc

        // Find earliest suffix position and truncate
        var earliestIndex = desc.endIndex
        for suffix in suffixes {
            if let range = desc.range(of: suffix) {
                if range.lowerBound < earliestIndex {
                    earliestIndex = range.lowerBound
                }
            }
        }

        if earliestIndex < desc.endIndex {
            companyName = String(desc[..<earliestIndex])
        }

        // Clean and validate
        companyName = companyName.trimmingCharacters(in: .whitespaces)
        guard companyName.count >= 3 else { return nil }

        return companyName
    }

    // MARK: - Trade Parsing

    /// Parse trade from raw record.
    private func parseTrade(
        from record: CharlesSchwabRawTransaction,
        companyTickerMap: [String: String] = [:]
    ) -> ParsedTrade? {
        // Handle ADR Mgmt Fee
        if record.action == "ADR Mgmt Fee" {
            return parseADRFee(record)
        }

        // Handle NRA Tax Adj - skip (handled in merge)
        if record.action == "NRA Tax Adj" {
            return nil
        }

        guard let actionType = CharlesSchwabActionType(rawAction: record.action),
              actionType.shouldImport else {
            return nil
        }

        guard let parsedDate = parseDate(record.date) else {
            return nil
        }

        let quantity = parseQuantity(record.quantity)
        let price = parseAmount(record.price)
        let amount = parseAmount(record.amount)

        // Option trades
        if actionType.isOptionTrade {
            guard let optionInfo = parseOptionSymbol(record.symbol) else {
                return nil
            }

            guard let tradeType = actionType.toParsedTradeType() else {
                return nil
            }

            return ParsedTrade(
                type: tradeType,
                ticker: optionInfo.underlyingTicker,
                quantity: abs(quantity),
                price: price,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: optionInfo,
                dividendInfo: nil,
                feeInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Dividends (standalone, not merged)
        if actionType.isDividend {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return nil }

            let dividendAmount = abs(amount)
            guard dividendAmount > .zero else { return nil }

            // Determine dividend type
            let dividendType: DividendType
            switch record.action {
            case "Qualified Dividend":
                dividendType = .qualified
            case "Long Term Cap Gain":
                dividendType = .capitalGain
            default:
                dividendType = .ordinary
            }

            let dividendInfo = DividendInfo(
                type: dividendType,
                grossAmount: dividendAmount,
                taxWithheld: .zero,
                issueId: record.itemIssueId.isEmpty ? nil : record.itemIssueId
            )

            return ParsedTrade(
                type: .dividend,
                ticker: symbol.uppercased(),
                quantity: .zero,
                price: .zero,
                totalAmount: dividendAmount,
                tradeDate: parsedDate,
                optionInfo: nil,
                dividendInfo: dividendInfo,
                feeInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Stock Split - treat as zero-cost buy
        if actionType == .stockSplit {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return nil }

            return ParsedTrade(
                type: .stockBuy,
                ticker: symbol.uppercased(),
                quantity: abs(quantity),
                price: .zero,
                totalAmount: .zero,
                tradeDate: parsedDate,
                optionInfo: nil,
                dividendInfo: nil,
                feeInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Symbol exchange / Corporate actions
        if actionType.isSymbolExchange {
            // Journaled Shares needs description check
            if actionType == .journaledShares {
                let descUpper = record.description.uppercased()

                // Stock Split (from TDA migration)
                if descUpper.contains("STOCK SPLIT") {
                    let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
                    guard !symbol.isEmpty else { return nil }

                    return ParsedTrade(
                        type: .stockBuy,
                        ticker: symbol.uppercased(),
                        quantity: abs(quantity),
                        price: .zero,
                        totalAmount: .zero,
                        tradeDate: parsedDate,
                        optionInfo: nil,
                        dividendInfo: nil,
                        feeInfo: nil,
                        note: "\(record.action): \(record.description)",
                        rawSource: "Charles Schwab"
                    )
                }

                // W-8 Withholding (TDA TRAN - W-8 WITHHOLDING)
                // These have non-zero amount and should be imported as taxWithholding
                if descUpper.contains("W-8 WITHHOLDING") && abs(amount) > 0 {
                    // Extract symbol from description like "W-8 WITHHOLDING (NVDA)"
                    var symbol = ""
                    if let openParen = record.description.range(of: "("),
                       let closeParen = record.description.range(of: ")") {
                        symbol = String(record.description[openParen.upperBound..<closeParen.lowerBound])
                    }

                    return ParsedTrade(
                        type: .taxWithholding,
                        ticker: symbol.uppercased(),
                        quantity: 0,
                        price: 0,
                        totalAmount: abs(amount),
                        tradeDate: parsedDate,
                        optionInfo: nil,
                        note: "\(record.action): \(record.description)",
                        rawSource: "Charles Schwab"
                    )
                }

                // Symbol exchange (SPAC mergers, etc.)
                guard descUpper.contains("EXCHANGE") else {
                    return nil  // Not exchange, split, or withholding - skip
                }
            }

            var symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return nil }

            // If symbol is CUSIP, try to look up ticker from map
            if isCUSIP(symbol) {
                if let companyName = extractCompanyName(from: record.description),
                   let ticker = companyTickerMap[companyName] {
                    symbol = ticker
                } else {
                    return nil  // Cannot resolve, skip
                }
            }

            let tradeType: ParsedTradeType = quantity < .zero ? .symbolExchangeOut : .symbolExchangeIn

            return ParsedTrade(
                type: tradeType,
                ticker: symbol.uppercased(),
                quantity: abs(quantity),
                price: .zero,
                totalAmount: .zero,
                tradeDate: parsedDate,
                optionInfo: nil,
                dividendInfo: nil,
                feeInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Cash transfers (deposits/withdraws)
        if actionType == .moneyLinkDeposit || actionType == .moneyLinkTransfer {
            // Determine deposit vs withdraw based on amount sign
            let tradeType: ParsedTradeType = amount >= 0 ? .deposit : .withdraw

            return ParsedTrade(
                type: tradeType,
                ticker: "",  // No symbol for cash transfers
                quantity: 0,
                price: 0,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Interest income (Bond Interest, Credit Interest)
        if actionType == .bondInterest || actionType == .creditInterest {
            guard abs(amount) > 0 else { return nil }  // Skip zero-amount records

            return ParsedTrade(
                type: .interestIncome,
                ticker: "",  // No symbol for interest
                quantity: 0,
                price: 0,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Tax withholding (NRA Tax Adj)
        if actionType == .nraTaxAdj {
            guard abs(amount) > 0 else { return nil }  // Skip zero-amount records

            return ParsedTrade(
                type: .taxWithholding,
                ticker: record.symbol.trimmingCharacters(in: .whitespaces),  // Keep related symbol
                quantity: 0,
                price: 0,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Dividend reinvest
        if actionType == .qualDivReinvest || actionType == .reinvestDividend {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)

            return ParsedTrade(
                type: .dividendReinvest,
                ticker: symbol.uppercased(),
                quantity: abs(quantity),
                price: price,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
        }

        // Stock trades (including Reinvest Shares)
        var symbol = record.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }

        // If symbol is CUSIP, try to look up ticker from map
        if isCUSIP(symbol) {
            if let companyName = extractCompanyName(from: record.description),
               let ticker = companyTickerMap[companyName] {
                symbol = ticker
            } else {
                return nil  // Cannot resolve, skip
            }
        }

        guard let tradeType = actionType.toParsedTradeType() else {
            return nil
        }

        return ParsedTrade(
            type: tradeType,
            ticker: symbol.uppercased(),
            quantity: abs(quantity),
            price: price,
            totalAmount: abs(amount),
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: nil,
            note: "\(record.action): \(record.description)",
            rawSource: "Charles Schwab"
        )
    }

    // MARK: - ADR Fee Parsing

    /// Parse ADR Management Fee record.
    private func parseADRFee(_ record: CharlesSchwabRawTransaction) -> ParsedTrade? {
        guard let parsedDate = parseDate(record.date) else {
            return nil
        }

        // Parse symbol from description: "TDA TRAN - ADR FEE (SE)" → "SE"
        guard let symbol = parseSymbolFromDescription(record.description),
              !symbol.isEmpty else {
            return nil
        }

        let amount = abs(parseAmount(record.amount))
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
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: feeInfo,
            note: record.description,
            rawSource: "Charles Schwab"
        )
    }

    /// Parse symbol from ADR fee description.
    /// Example: "TDA TRAN - ADR FEE (SE)" → "SE"
    private func parseSymbolFromDescription(_ description: String) -> String? {
        let pattern = #"\(([A-Z]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: description,
                  range: NSRange(description.startIndex..., in: description)
              ),
              let range = Range(match.range(at: 1), in: description) else {
            return nil
        }
        return String(description[range])
    }

    // MARK: - Value Parsing

    /// Parse date string.
    /// Format: MM/DD/YYYY or MM/DD/YYYY as of MM/DD/YYYY
    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)

        // Handle "as of" format, take first date
        let primaryDate: String
        if let asOfRange = trimmed.range(of: " as of ") {
            primaryDate = String(trimmed[..<asOfRange.lowerBound])
        } else {
            primaryDate = trimmed
        }

        return Self.tradeDateFormatter.date(from: primaryDate)
    }

    /// Parse quantity string.
    private func parseQuantity(_ quantityString: String) -> Decimal {
        let trimmed = quantityString.trimmingCharacters(in: .whitespaces)
        return Decimal(string: trimmed) ?? .zero
    }

    /// Parse amount string (remove $ and commas).
    private func parseAmount(_ amountString: String) -> Decimal {
        var cleaned = amountString.trimmingCharacters(in: .whitespaces)
        cleaned = cleaned.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned) ?? .zero
    }

    // MARK: - Option Symbol Parsing

    /// Parse CS option symbol.
    /// Format: IMMR 02/20/2026 5.00 C
    /// - Parameter symbol: CS option symbol
    /// - Returns: Parsed option info
    public func parseOptionSymbol(_ symbol: String) -> ParsedOptionInfo? {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)

        // Regex: TICKER MM/DD/YYYY STRIKE C/P
        let pattern = #"^([A-Z]+)\s+(\d{2}/\d{2}/\d{4})\s+([\d.]+)\s+([CP])$"#

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
        guard let tickerRange = Range(match.range(at: 1), in: trimmed),
              let dateRange = Range(match.range(at: 2), in: trimmed),
              let strikeRange = Range(match.range(at: 3), in: trimmed),
              let typeRange = Range(match.range(at: 4), in: trimmed)
        else {
            return nil
        }

        let ticker = String(trimmed[tickerRange]).uppercased()
        let dateStr = String(trimmed[dateRange])
        let strikeStr = String(trimmed[strikeRange])
        let typeStr = String(trimmed[typeRange]).uppercased()

        // Parse option type
        let optionType: OptionType
        switch typeStr {
        case "C":
            optionType = .call
        case "P":
            optionType = .put
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
}
