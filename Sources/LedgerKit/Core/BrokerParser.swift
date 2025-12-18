import Foundation

// MARK: - BrokerParser Protocol

/// A protocol that defines the interface for parsing brokerage transaction data.
///
/// Implement this protocol to add support for a new broker. Each parser should
/// convert broker-specific data formats into the unified `ParsedTrade` format.
///
/// Example:
/// ```swift
/// let parser = CharlesSchwabParser()
/// let trades = try parser.parse(jsonData)
/// ```
public protocol BrokerParser: Sendable {

    /// The display name of the broker.
    static var brokerName: String { get }

    /// The file formats supported by this parser.
    static var supportedFormats: [FileFormat] { get }

    /// Parses raw data and returns an array of parsed trades.
    ///
    /// - Parameter data: The raw data from the broker's export file.
    /// - Returns: An array of `ParsedTrade` objects.
    /// - Throws: `ParserError` if parsing fails.
    func parse(_ data: Data) throws -> [ParsedTrade]

    /// Parses raw data and returns parsed trades along with any warnings.
    ///
    /// Use this method when you need to capture warnings about skipped or
    /// problematic records without failing the entire parse operation.
    ///
    /// - Parameter data: The raw data from the broker's export file.
    /// - Returns: A tuple containing the parsed trades and any warning messages.
    /// - Throws: `ParserError` if parsing fails.
    func parseWithWarnings(_ data: Data) throws -> (trades: [ParsedTrade], warnings: [String])
}

// MARK: - Default Implementation

public extension BrokerParser {

    /// Default implementation that calls `parseWithWarnings` and discards warnings.
    func parse(_ data: Data) throws -> [ParsedTrade] {
        let (trades, _) = try parseWithWarnings(data)
        return trades
    }
}
