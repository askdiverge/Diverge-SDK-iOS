import Foundation

/// Errors thrown while configuring or using the Diverge SDK.
public enum DivergeError: Error, Sendable, Equatable, LocalizedError {
    /// The provided API key was empty or whitespace-only.
    case invalidAPIKey
    /// `Diverge.configure` has not been called yet.
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            "API key must not be blank."
        case .notConfigured:
            "Call Diverge.configure before using Diverge.shared."
        }
    }
}
