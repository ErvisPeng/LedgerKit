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

    // MARK: - Initialization

    public init() {}

    // MARK: - Parsing

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        // TODO: Implement in Phase 3
        // This is a placeholder implementation for Phase 1
        guard !data.isEmpty else {
            throw ParserError.emptyData
        }

        // Placeholder - will be implemented when migrating from PortfolioNow
        return ([], ["FirstradeParser not yet implemented"])
    }
}
