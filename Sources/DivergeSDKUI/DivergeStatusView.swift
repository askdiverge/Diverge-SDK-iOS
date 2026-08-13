import DivergeSDK
import SwiftUI

/// Lightweight status view showing SDK version and configured environment.
///
/// Ship in the `DivergeSDKUI` product so core hosts need not link SwiftUI.
@MainActor
public struct DivergeStatusView: View {
    private let client: DivergeClient?

    public init(client: DivergeClient?) {
        self.client = client
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diverge SDK")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(Diverge.version)")
                .font(.body)
                .accessibilityLabel("SDK version \(Diverge.version)")
            if let client {
                Text("Environment \(client.configuration.environment.rawValue)")
                    .font(.body)
                    .accessibilityLabel("Environment \(client.configuration.environment.rawValue)")
                Text(client.apiBaseURL.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("API base URL \(client.apiBaseURL.absoluteString)")
            } else {
                Text("Not configured")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("SDK not configured")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .contain)
    }

    /// Stable, cross-platform dump used by snapshot tests (avoids pixel diffs across OS).
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
