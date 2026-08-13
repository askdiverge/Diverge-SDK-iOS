import Foundation

/// Configuration used to initialize the Diverge SDK.
public struct Configuration: Sendable, Equatable, CustomStringConvertible {
    /// API key issued for the host application.
    public let apiKey: String
    /// Target backend environment.
    public let environment: Environment

    /// Creates a configuration.
    /// - Parameters:
    ///   - apiKey: Non-empty API key.
    ///   - environment: Sandbox or production.
    public init(apiKey: String, environment: Environment) {
        self.apiKey = apiKey
        self.environment = environment
    }

    /// Redacted description — never logs the full API key.
    public var description: String {
        "Configuration(apiKey: \(Self.redact(apiKey)), environment: \(environment.rawValue))"
    }

    /// Redacts an API key for logs (keeps a short prefix/suffix when long enough).
    public static func redact(_ apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "***" }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
