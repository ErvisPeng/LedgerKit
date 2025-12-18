import Foundation

// MARK: - CharlesSchwabParserError

/// Errors specific to Charles Schwab JSON parsing.
public enum CharlesSchwabParserError: Error, Sendable, LocalizedError {
    /// The input data is empty or cannot be decoded.
    case invalidData

    /// The JSON structure is invalid.
    case invalidJSON(String)

    /// A date string could not be parsed.
    case invalidDateFormat(String)

    /// A general parsing error with details.
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Unable to read JSON file. Please ensure the file is valid."
        case .invalidJSON(let message):
            return "Invalid JSON format: \(message)"
        case .invalidDateFormat(let dateString):
            return "Invalid date format: \(dateString)"
        case .parsingFailed(let message):
            return "JSON parsing failed: \(message)"
        }
    }
}
