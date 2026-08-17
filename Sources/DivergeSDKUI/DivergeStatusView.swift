import DivergeSDK
import SwiftUI

/// Lightweight status view showing SDK version and configured environment.
///
/// Ship in the `DivergeSDKUI` product so core hosts need not link SwiftUI.
///
/// Text colors are fixed AA-safe values (normal text ≥ 4.5:1 on white / light surfaces),
/// not system `Color.secondary`, so contrast stays predictable inside host apps.
@MainActor
public struct DivergeStatusView: View {
    /// Near-black body text — ≈17:1 on white.
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Secondary body/footnote — ≈8.9:1 on white (≥ 4.5:1 AA).
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)

    private let client: DivergeClient?

    public init(client: DivergeClient?) {
        self.client = client
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diverge SDK")
                .font(.headline)
                .foregroundColor(Self.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h2)
            Text("Version \(Diverge.version)")
                .font(.body)
                .foregroundColor(Self.primaryText)
                .accessibilityLabel("SDK version \(Diverge.version)")
            if let client {
                Text("Environment \(client.configuration.environment.rawValue)")
                    .font(.body)
                    .foregroundColor(Self.primaryText)
                    .accessibilityLabel("Environment \(client.configuration.environment.rawValue)")
                Text(client.apiBaseURL.absoluteString)
                    .font(.footnote)
                    .foregroundColor(Self.secondaryText)
                    .accessibilityLabel("API base URL \(client.apiBaseURL.absoluteString)")
            } else {
                Text("Not configured")
                    .font(.body)
                    .foregroundColor(Self.secondaryText)
                    .accessibilityLabel("SDK not configured")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diverge.statusView")
    }

    /// Stable accessibility string dump used by a11y contract tests (not pixel snapshots).
    public nonisolated static func accessibilityDump(client: DivergeClient?) -> String {
        var lines = [
            "title: Diverge SDK",
            "version: \(Diverge.version)"
        ]
        if let client {
            lines.append("environment: \(client.configuration.environment.rawValue)")
            lines.append("apiBaseURL: \(client.apiBaseURL.absoluteString)")
        } else {
            lines.append("state: not-configured")
        }
        return lines.joined(separator: "\n")
    }
}
