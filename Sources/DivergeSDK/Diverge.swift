import Foundation

/// Diverge ecommerce SDK namespace.
///
/// Import the `DivergeSDK` module, then call ``configure(_:)`` before using ``shared``.
///
/// `configure` and `shared` are synchronized with a lock; call `configure` once at app launch.
public enum Diverge {
    /// Semantic version of this SDK build (from the repo `VERSION` file).
    public static var version: String {
        VersionInfo.current
    }

    private static let lock = NSLock()
    /// Synchronized via `lock`; marked unsafe for Swift 6 global mutable state checking.
    private nonisolated(unsafe) static var _shared: DivergeClient?

    /// The shared client after a successful ``configure(_:)``.
    /// - Throws: ``DivergeError/notConfigured`` if configure was never called.
    public static var shared: DivergeClient {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            guard let client = _shared else {
                throw DivergeError.notConfigured
            }
            return client
        }
    }

    /// Whether ``configure(_:)`` has been called successfully.
    public static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _shared != nil
    }

    /// Configures the SDK and replaces any previous shared client.
    /// - Parameter configuration: API key and environment.
    /// - Returns: The new shared ``DivergeClient``.
    /// - Throws: ``DivergeError/invalidAPIKey`` if the key is blank.
    @discardableResult
    public static func configure(_ configuration: Configuration) throws -> DivergeClient {
        let trimmed = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DivergeError.invalidAPIKey
        }
        let normalized = Configuration(apiKey: trimmed, environment: configuration.environment)
        let client = DivergeClient(configuration: normalized)
        lock.lock()
        _shared = client
        lock.unlock()
        return client
    }

    /// Resets the shared client.
    ///
    /// Intended for unit tests. Host apps should not call this in production.
    @_spi(Testing)
    public static func reset() {
        lock.lock()
        _shared = nil
        lock.unlock()
    }
}
