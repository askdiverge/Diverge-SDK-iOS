import Foundation
import AIConversation

/// Values baked in from `Samples/iOS/Config/*.xcconfig` via Info.plist.
enum SampleConfig {
    /// Sample-only fallback when Info.plist has no host.
    static let developmentBaseURL = URL(string: "https://dev.api.dialogintelligens.dk")!

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
