import AIConversation
import Combine
import Foundation

/// Mutable box for Sample host hooks — escaping `AIChat.Configuration` closures capture this
/// class so UITest probes update while the chat sheet is presented.
final class HostProbe: ObservableObject, @unchecked Sendable {
    @Published var lastAddedProduct: String?
    @Published var lastOpenedURL: String?
    /// Latest visitor JWT for `resetConversation` (`POST /auth/reset` needs the current token).
    var visitorToken = ""
}

/// Which Chatbot API the Sample talks to; the build configuration picks the default.
enum Backend: String, CaseIterable {
    case production
    case development
    case local

    var title: String {
        switch self {
        case .production: "Production"
        case .development: "Development"
        case .local: "Local"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .production: DivergeAPI.productionBaseURL
        case .development: SampleConfig.developmentBaseURL
        case .local: SampleConfig.localBaseURL
        }
    }

    var footnote: String {
        switch self {
        case .production:
            "Talks to \(DivergeAPI.productionBaseURL.absoluteString)"
        case .development:
            "Talks to \(SampleConfig.developmentBaseURL.absoluteString) (shared dev API)."
        case .local:
            "Talks to a local dialogintelligens API. Start it with docker compose."
        }
    }

    static var fromBuildSettings: Backend {
        Backend(rawValue: SampleConfig.environmentName) ?? .development
    }
}
