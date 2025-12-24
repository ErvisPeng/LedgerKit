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
        var warnings: [String] = []

        // Build company name to ticker mapping for CUSIP resolution
        let companyTickerMap = buildCompanyTickerMap(from: records)

        // Step 1: Build tax lookup map for precise dividend-tax pairing
        // Key: (Date, Symbol, ItemIssueId) → Tax record
        let taxRecords = buildTaxLookup(from: records)

        // Step 2: Track which tax records have been paired
        var pairedTaxIndices: Set<Int> = []

        // Step 3: Process all records
        for (index, record) in records.enumerated() {
            // Skip NRA Tax Adj - will be paired with dividends
            if record.action == "NRA Tax Adj" {
                continue
            }

            // Parse action type
            guard let actionType = CharlesSchwabActionType(rawAction: record.action) else {
                continue
            }

            // Handle dividend records - try to pair with tax
            if actionType.isDividend {
                if let trade = parseDividendWithTaxPairing(
                    record,
                    taxRecords: taxRecords,
                    pairedTaxIndices: &pairedTaxIndices
                ) {
                    trades.append(trade)
                }
                continue
            }

            // All other record types - normal processing
            let (trade, warning) = parseTrade(from: record, companyTickerMap: companyTickerMap)
            if let trade = trade {
                trades.append(trade)
            }
            if let warning = warning {
                warnings.append(warning)
            }
        }

        // Step 4: Process unpaired NRA Tax Adj as standalone taxWithholding
        for (index, record) in records.enumerated() {
            guard record.action == "NRA Tax Adj",
                  !pairedTaxIndices.contains(index) else {
                continue
            }

            // This NRA Tax Adj was not paired with a dividend - record as standalone
            guard let parsedDate = parseDate(record.date) else { continue }
            let amount = parseAmount(record.amount)
            guard abs(amount) > 0 else { continue }

            let trade = ParsedTrade(
                type: .taxWithholding,
                ticker: record.symbol.trimmingCharacters(in: .whitespaces).uppercased(),
                quantity: 0,
                price: 0,
                totalAmount: -abs(amount),  // Tax is cash outflow (negative)
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            )
            trades.append(trade)
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

    // MARK: - Dividend + Tax Pairing

    /// Key for precise dividend-tax pairing
    private struct DividendTaxKey: Hashable {
        let date: String
        let symbol: String
        let itemIssueId: String
    }

    /// Build lookup map for NRA Tax Adj records
    private func buildTaxLookup(
        from records: [CharlesSchwabRawTransaction]
    ) -> [DividendTaxKey: (index: Int, record: CharlesSchwabRawTransaction)] {
        var map: [DividendTaxKey: (index: Int, record: CharlesSchwabRawTransaction)] = [:]

        for (index, record) in records.enumerated() {
            guard record.action == "NRA Tax Adj" else { continue }

            let key = DividendTaxKey(
                date: record.date,
                symbol: record.symbol.trimmingCharacters(in: .whitespaces).uppercased(),
                itemIssueId: record.itemIssueId
            )
            map[key] = (index, record)
        }

        return map
    }

    /// Parse dividend and pair with corresponding tax record
    private func parseDividendWithTaxPairing(
        _ record: CharlesSchwabRawTransaction,
        taxRecords: [DividendTaxKey: (index: Int, record: CharlesSchwabRawTransaction)],
        pairedTaxIndices: inout Set<Int>
    ) -> ParsedTrade? {
        guard let parsedDate = parseDate(record.date) else { return nil }

        let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }

        let grossAmount = abs(parseAmount(record.amount))
        guard grossAmount > .zero else { return nil }

        // Try to find matching tax record
        let key = DividendTaxKey(
            date: record.date,
            symbol: symbol.uppercased(),
            itemIssueId: record.itemIssueId
        )

        var taxAmount: Decimal = .zero
        if let taxEntry = taxRecords[key], !pairedTaxIndices.contains(taxEntry.index) {
            taxAmount = abs(parseAmount(taxEntry.record.amount))
            pairedTaxIndices.insert(taxEntry.index)
        }

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
            grossAmount: grossAmount,
            taxWithheld: taxAmount,
            issueId: record.itemIssueId.isEmpty ? nil : record.itemIssueId
        )

        return ParsedTrade(
            type: .dividend,
            ticker: symbol.uppercased(),
            quantity: .zero,
            price: .zero,
            totalAmount: dividendInfo.netAmount,  // Net amount (gross - tax)
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: dividendInfo,
            feeInfo: nil,
            note: "\(record.action): \(record.description)",
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
    /// - Returns: Tuple of (ParsedTrade?, warning message?)
    private func parseTrade(
        from record: CharlesSchwabRawTransaction,
        companyTickerMap: [String: String] = [:]
    ) -> (ParsedTrade?, String?) {
        // Handle ADR Mgmt Fee
        if record.action == "ADR Mgmt Fee" {
            return (parseADRFee(record), nil)
        }

        // Handle NRA Tax Adj - skip (handled in merge)
        if record.action == "NRA Tax Adj" {
            return (nil, nil)
        }

        guard let actionType = CharlesSchwabActionType(rawAction: record.action),
              actionType.shouldImport else {
            return (nil, nil)
        }

        guard let parsedDate = parseDate(record.date) else {
            return (nil, nil)
        }

        let quantity = parseQuantity(record.quantity)
        let price = parseAmount(record.price)
        let amount = parseAmount(record.amount)
        let commission = parseAmount(record.feesAndComm)

        // Build feeInfo if commission exists
        let tradeFeeInfo: FeeInfo? = commission > .zero
            ? FeeInfo(type: .tradingCommission, amount: commission)
            : nil

        // Option trades
        if actionType.isOptionTrade {
            guard let optionInfo = parseOptionSymbol(record.symbol) else {
                return (nil, nil)
            }

            guard let tradeType = actionType.toParsedTradeType() else {
                return (nil, nil)
            }

            return (ParsedTrade(
                type: tradeType,
                ticker: optionInfo.underlyingTicker,
                quantity: abs(quantity),
                price: price,
                totalAmount: amount,  // Keep original sign
                tradeDate: parsedDate,
                optionInfo: optionInfo,
                dividendInfo: nil,
                feeInfo: tradeFeeInfo,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Dividends (standalone, not merged)
        if actionType.isDividend {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return (nil, nil) }

            let dividendAmount = abs(amount)
            guard dividendAmount > .zero else { return (nil, nil) }

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

            return (ParsedTrade(
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
            ), nil)
        }

        // Stock Split - treat as zero-cost buy
        if actionType == .stockSplit {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return (nil, nil) }

            return (ParsedTrade(
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
            ), nil)
        }

        // Symbol exchange / Corporate actions
        if actionType.isSymbolExchange {
            // Journaled Shares needs description check
            if actionType == .journaledShares {
                let descUpper = record.description.uppercased()

                // Stock Split (from TDA migration)
                if descUpper.contains("STOCK SPLIT") {
                    let symbol = record.symbol.trimmingCharacters(in: .whitespaces)
                    guard !symbol.isEmpty else { return (nil, nil) }

                    return (ParsedTrade(
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
                    ), nil)
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

                    return (ParsedTrade(
                        type: .taxWithholding,
                        ticker: symbol.uppercased(),
                        quantity: 0,
                        price: 0,
                        totalAmount: -abs(amount),  // Tax is cash outflow (negative)
                        tradeDate: parsedDate,
                        optionInfo: nil,
                        note: "\(record.action): \(record.description)",
                        rawSource: "Charles Schwab"
                    ), nil)
                }

                // CASH MOVEMENT (TDA TRAN - CASH MOVEMENT OF...)
                // These represent cash transfers during account migrations and should be recorded
                if descUpper.contains("CASH MOVEMENT") && abs(amount) > 0 {
                    let tradeType: ParsedTradeType = amount >= 0 ? .deposit : .withdraw
                    return (ParsedTrade(
                        type: tradeType,
                        ticker: "",
                        quantity: 0,
                        price: 0,
                        totalAmount: amount,  // Keep original sign
                        tradeDate: parsedDate,
                        optionInfo: nil,
                        note: "\(record.action): \(record.description)",
                        rawSource: "Charles Schwab"
                    ), nil)
                }

                // Symbol exchange (SPAC mergers, etc.)
                guard descUpper.contains("EXCHANGE") else {
                    return (nil, nil)  // Not exchange, split, withholding, or cash movement - skip
                }
            }

            var symbol = record.symbol.trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { return (nil, nil) }

            // If symbol is CUSIP, try to look up ticker from map
            if isCUSIP(symbol) {
                if let companyName = extractCompanyName(from: record.description),
                   let ticker = companyTickerMap[companyName] {
                    symbol = ticker
                } else {
                    // Cannot resolve CUSIP to ticker - return warning
                    let warning = "無法解析 CUSIP '\(symbol)': \(record.action) - \(record.description) (數量: \(record.quantity))"
                    return (nil, warning)
                }
            }

            let tradeType: ParsedTradeType = quantity < .zero ? .symbolExchangeOut : .symbolExchangeIn

            return (ParsedTrade(
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
            ), nil)
        }

        // Cash transfers (deposits/withdraws)
        if actionType == .moneyLinkDeposit || actionType == .moneyLinkTransfer ||
           actionType == .fundsDeposited || actionType == .fundsWithdrawn {
            // Determine deposit vs withdraw based on amount sign or action type
            let tradeType: ParsedTradeType
            if actionType == .fundsWithdrawn {
                tradeType = .withdraw
            } else if actionType == .fundsDeposited {
                tradeType = .deposit
            } else {
                tradeType = amount >= 0 ? .deposit : .withdraw
            }

            return (ParsedTrade(
                type: tradeType,
                ticker: "",  // No symbol for cash transfers
                quantity: 0,
                price: 0,
                totalAmount: amount,  // Keep original sign: positive for deposit, negative for withdraw
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Internal Transfer (account migrations)
        if actionType == .internalTransfer {
            guard abs(amount) > 0 else { return (nil, nil) }  // Skip stock-only transfers (no cash)

            // Determine deposit vs withdraw based on amount sign
            let tradeType: ParsedTradeType = amount >= 0 ? .deposit : .withdraw

            return (ParsedTrade(
                type: tradeType,
                ticker: "",  // No symbol for cash transfers
                quantity: 0,
                price: 0,
                totalAmount: amount,  // Keep original sign
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Interest income (Bond Interest, Credit Interest)
        if actionType == .bondInterest || actionType == .creditInterest {
            guard abs(amount) > 0 else { return (nil, nil) }  // Skip zero-amount records

            return (ParsedTrade(
                type: .interestIncome,
                ticker: "",  // No symbol for interest
                quantity: 0,
                price: 0,
                totalAmount: abs(amount),
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Tax withholding (NRA Tax Adj)
        if actionType == .nraTaxAdj {
            guard abs(amount) > 0 else { return (nil, nil) }  // Skip zero-amount records

            return (ParsedTrade(
                type: .taxWithholding,
                ticker: record.symbol.trimmingCharacters(in: .whitespaces),  // Keep related symbol
                quantity: 0,
                price: 0,
                totalAmount: -abs(amount),  // Tax is cash outflow (negative)
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Cash In Lieu (fractional share cash payment from stock split/merger)
        if actionType == .cashInLieu {
            guard abs(amount) > 0 else { return (nil, nil) }  // Skip zero-amount records

            return (ParsedTrade(
                type: .dividend,
                ticker: record.symbol.trimmingCharacters(in: .whitespaces).uppercased(),
                quantity: 0,
                price: 0,
                totalAmount: abs(amount),  // Cash received (positive)
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Interest Adjustment (margin interest adjustment)
        if actionType == .interestAdj {
            guard abs(amount) > 0 else { return (nil, nil) }  // Skip zero-amount records

            return (ParsedTrade(
                type: .fee,
                ticker: "",  // No symbol for interest adjustment
                quantity: 0,
                price: 0,
                totalAmount: amount,  // Keep original sign (usually negative for expense)
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Journal - Other: FOREIGN WITHHOLDING (tax withholding from foreign dividends)
        // These have CUSIP in symbol field and description like "FOREIGN WITHHOLDING 31046423609"
        if actionType == .journalOther {
            let descUpper = record.description.uppercased()

            if descUpper.contains("FOREIGN WITHHOLDING") || descUpper.contains("WITHHOLDING") {
                guard abs(amount) > 0 else { return (nil, nil) }  // Skip zero-amount records

                // Try to extract symbol from CUSIP if possible, otherwise leave empty
                // Symbol field contains CUSIP like "13462K109", not ticker
                let ticker = ""  // Cannot resolve CUSIP to ticker without mapping

                return (ParsedTrade(
                    type: .taxWithholding,
                    ticker: ticker,
                    quantity: 0,
                    price: 0,
                    totalAmount: -abs(amount),  // Tax is cash outflow (negative)
                    tradeDate: parsedDate,
                    optionInfo: nil,
                    feeInfo: FeeInfo(type: .taxWithholding, amount: abs(amount)),
                    note: "\(record.action): \(record.description)",
                    rawSource: "Charles Schwab"
                ), nil)
            }

            // Other Journal - Other records without known patterns are skipped
            return (nil, nil)
        }

        // Dividend reinvest
        // Note: CS has two separate records for dividend reinvestment:
        // 1. "Qual Div Reinvest" / "Reinvest Dividend" - dividend income (often empty symbol/quantity)
        // 2. "Reinvest Shares" - actual stock purchase (has symbol, quantity, price)
        // We skip #1 if symbol is empty, and let #2 be handled as stockBuy
        if actionType == .qualDivReinvest || actionType == .reinvestDividend {
            let symbol = record.symbol.trimmingCharacters(in: .whitespaces)

            // Skip if symbol is empty or quantity is zero (will be handled by "Reinvest Shares")
            guard !symbol.isEmpty, abs(quantity) > 0 else { return (nil, nil) }

            return (ParsedTrade(
                type: .dividendReinvest,
                ticker: symbol.uppercased(),
                quantity: abs(quantity),
                price: price,
                totalAmount: amount,  // Keep original sign
                tradeDate: parsedDate,
                optionInfo: nil,
                note: "\(record.action): \(record.description)",
                rawSource: "Charles Schwab"
            ), nil)
        }

        // Stock trades (including Reinvest Shares)
        var symbol = record.symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return (nil, nil) }

        // If symbol is CUSIP, try to look up ticker from map
        if isCUSIP(symbol) {
            if let companyName = extractCompanyName(from: record.description),
               let ticker = companyTickerMap[companyName] {
                symbol = ticker
            } else {
                // Cannot resolve CUSIP to ticker - return warning
                let warning = "無法解析 CUSIP '\(symbol)': \(record.action) - \(record.description) (數量: \(record.quantity))"
                return (nil, warning)
            }
        }

        guard let tradeType = actionType.toParsedTradeType() else {
            return (nil, nil)
        }

        return (ParsedTrade(
            type: tradeType,
            ticker: symbol.uppercased(),
            quantity: abs(quantity),
            price: price,
            totalAmount: amount,  // Keep original sign: negative for buys, positive for sells
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: tradeFeeInfo,
            note: "\(record.action): \(record.description)",
            rawSource: "Charles Schwab"
        ), nil)
    }

    // MARK: - ADR Fee Parsing

    /// Parse ADR Management Fee record.
    private func parseADRFee(_ record: CharlesSchwabRawTransaction) -> ParsedTrade? {
        guard let parsedDate = parseDate(record.date) else {
            return nil
        }

        // Use symbol from record, or extract first word from description as fallback
        let symbol: String
        if !record.symbol.isEmpty {
            symbol = record.symbol
        } else {
            // Extract first word (ticker) from description
            // Example: "ARM HOLDINGS PLC SPONSORED ADS (SE) ADR FEES" → "ARM"
            let firstWord = record.description.split(separator: " ").first.map(String.init) ?? ""
            guard !firstWord.isEmpty else { return nil }
            symbol = firstWord
        }

        let feeAmount = abs(parseAmount(record.amount))
        guard feeAmount > .zero else { return nil }

        let feeInfo = FeeInfo(
            type: .adrMgmtFee,
            amount: feeAmount
        )

        return ParsedTrade(
            type: .fee,
            ticker: symbol,
            quantity: .zero,
            price: .zero,
            totalAmount: -feeAmount,  // Fee is cash outflow (negative)
            tradeDate: parsedDate,
            optionInfo: nil,
            dividendInfo: nil,
            feeInfo: feeInfo,
            note: record.description,
            rawSource: "Charles Schwab"
        )
    }

    // MARK: - Value Parsing

    /// Parse date string.
    /// Format: MM/DD/YYYY or MM/DD/YYYY as of MM/DD/YYYY
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

        // Parse using existing formatter to get a Date (ignoring time/zone correctness for a moment)
        guard let date = Self.tradeDateFormatter.date(from: primaryDate) else {
            return nil
        }
        
        // Manual component parsing to be independent of formatter's timezone assumptions
        let components = primaryDate.split(separator: "/")
        guard components.count == 3,
              let month = Int(components[0]),
              let day = Int(components[1]),
              let year = Int(components[2]) else {
            return nil
        }

        // Construct date at 09:30 AM America/New_York
        var calendar = Calendar(identifier: .gregorian)
        if let nyTimeZone = TimeZone(identifier: "America/New_York") {
            calendar.timeZone = nyTimeZone
        }
        
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = 9
        dateComponents.minute = 30
        dateComponents.second = 0
        
        return calendar.date(from: dateComponents)
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
