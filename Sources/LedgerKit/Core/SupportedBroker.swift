import Foundation

// MARK: - SupportedBroker

/// Enumeration of brokers supported by LedgerKit.
public enum SupportedBroker: String, Sendable, CaseIterable {
    /// Charles Schwab - supports JSON export format
    case charlesSchwab = "Charles Schwab"

    /// Firstrade - supports CSV export format
    case firstrade = "Firstrade"

    /// The display name for this broker.
    public var displayName: String {
        rawValue
    }

    /// The file formats supported by this broker.
    public var supportedFormats: [FileFormat] {
        switch self {
        case .charlesSchwab:
            return [.json]
        case .firstrade:
            return [.csv]
        }
    }
}

// MARK: - BrokerParserFactory

/// Factory for creating broker parsers.
public enum BrokerParserFactory {

    /// Creates a parser for the specified broker.
    ///
    /// - Parameter broker: The broker to create a parser for.
    /// - Returns: A parser instance conforming to `BrokerParser`.
    public static func parser(for broker: SupportedBroker) -> any BrokerParser {
        switch broker {
        case .charlesSchwab:
            return CharlesSchwabParser()
        case .firstrade:
            return FirstradeParser()
        }
    }
}
