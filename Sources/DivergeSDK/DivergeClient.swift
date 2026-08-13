import Foundation

/// Configured SDK session. Obtain via ``Diverge/configure(_:)`` or ``Diverge/shared``.
public final class DivergeClient: Sendable {
    /// Active configuration for this session.
    public let configuration: Configuration

    /// SDK semantic version.
    public var version: String {
        Diverge.version
    }

    /// Resolved API base URL for the configured environment.
    public var apiBaseURL: URL {
        configuration.environment.apiBaseURL
    }

    init(configuration: Configuration) {
        self.configuration = configuration
    }
}
