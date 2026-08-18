import Foundation

/// Deployment environment for the Diverge SDK.
///
/// Named `DivergeEnvironment` to avoid colliding with SwiftUI's `Environment`.
/// Raw values are lowercase (`sandbox`, `production`) on all platforms. Android
/// exposes the same wire values via `DivergeEnvironment.wireName`.
public enum DivergeEnvironment: String, Sendable, CaseIterable, Equatable {
    case sandbox
    case production

    private static let sandboxURL = makeURL("https://sandbox.api.askdiverge.ai")
    private static let productionURL = makeURL("https://api.askdiverge.ai")

    /// API base URL for this environment (placeholder hosts until backends are wired).
    public var apiBaseURL: URL {
        switch self {
        case .sandbox:
            Self.sandboxURL
        case .production:
            Self.productionURL
        }
    }

    private static func makeURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid Diverge API base URL constant: \(string)")
        }
        return url
    }
}
