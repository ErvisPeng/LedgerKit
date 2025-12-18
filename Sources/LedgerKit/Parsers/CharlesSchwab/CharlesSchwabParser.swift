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

    // MARK: - Initialization

    public init() {}

    // MARK: - Parsing

    public func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String]) {
        // TODO: Implement in Phase 4
        // This is a placeholder implementation for Phase 1
        guard !data.isEmpty else {
            throw ParserError.emptyData
        }

        // Placeholder - will be implemented when migrating from PortfolioNow
        return ([], ["CharlesSchwabParser not yet implemented"])
    }
}
