import Foundation

// MARK: - ParserError

/// Errors that can occur during parsing of broker data.
public enum ParserError: Error, Sendable, LocalizedError {
    /// The input data is empty or nil.
    case emptyData

    /// The data could not be decoded as the expected format.
    case invalidFormat(String)

    /// A required field is missing from the data.
    case missingField(String)

    /// A date string could not be parsed.
    case invalidDate(String)

    /// A numeric value could not be parsed.
    case invalidNumber(String)

    /// The file header is invalid or missing expected columns.
    case invalidHeader(expected: [String], actual: [String])

    /// A general parsing error with a custom message.
    case parsingFailed(String)

    /// No valid trades were found in the data.
    case noTradesFound

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "The input data is empty."
        case .invalidFormat(let message):
            return "Invalid data format: \(message)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .invalidDate(let dateString):
            return "Invalid date format: \(dateString)"
        case .invalidNumber(let value):
            return "Invalid numeric value: \(value)"
        case .invalidHeader(let expected, let actual):
            return "Invalid header. Expected: \(expected.joined(separator: ", ")). Got: \(actual.joined(separator: ", "))"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .noTradesFound:
            return "No valid trades found in the data."
        }
    }
}
