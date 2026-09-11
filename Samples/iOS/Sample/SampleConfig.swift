import Foundation
import AIConversation

/// Values baked in from `Samples/iOS/Config/*.xcconfig` via Info.plist.
enum SampleConfig {
    /// Shared development API (`development` branch / `dev.api`). Sample-only — not a public SDK constant.
    static let developmentBaseURL = URL(string: "https://dev.api.dialogintelligens.dk")!
    /// Local stand-in backend. Simulator loopback is the Mac.
    static let localBaseURL = URL(string: "http://127.0.0.1:3000")!

    static var environmentName: String {
        (Bundle.main.object(forInfoDictionaryKey: "DivergeAPIEnvironment") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "development"
    }

    static var apiBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "DivergeAPIBaseURL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return Self.developmentBaseURL
    }
}
