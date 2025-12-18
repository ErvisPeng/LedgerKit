import Foundation

// MARK: - FileFormat

/// Supported file formats for broker data exports.
public enum FileFormat: String, Sendable, CaseIterable {
    /// JSON format (e.g., Charles Schwab)
    case json

    /// CSV format (e.g., Firstrade)
    case csv

    /// XML format
    case xml

    /// The file extension for this format.
    public var fileExtension: String {
        rawValue
    }

    /// A human-readable description of the format.
    public var displayName: String {
        switch self {
        case .json:
            return "JSON"
        case .csv:
            return "CSV"
        case .xml:
            return "XML"
        }
    }
}
