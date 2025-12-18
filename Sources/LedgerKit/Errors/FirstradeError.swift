import Foundation

// MARK: - FirstradeParserError

/// Errors specific to Firstrade CSV parsing.
public enum FirstradeParserError: Error, Sendable, LocalizedError {
    /// The input data is empty or cannot be decoded as UTF-8.
    case invalidData

    /// The CSV header does not match expected Firstrade format.
    case invalidHeader

    /// A date string could not be parsed.
    case invalidDateFormat(String)

    /// A general parsing error with details.
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Unable to read CSV file. Please ensure the file is valid UTF-8 encoded."
        case .invalidHeader:
            return "Invalid CSV header. Please ensure this is a Firstrade transaction history file."
        case .invalidDateFormat(let dateString):
            return "Invalid date format: \(dateString)"
        case .parsingFailed(let message):
            return "CSV parsing failed: \(message)"
        }
    }
}
