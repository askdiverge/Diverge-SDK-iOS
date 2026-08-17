import DivergeSDK
import DivergeSDKUI
import SwiftUI

struct ContentView: View {
    /// Sample chrome — matches SDK AA-safe primary (~17:1 on white).
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Sample secondary — ~8.9:1 on white.
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)
    /// Error text on light red wash — ≥ 4.5:1.
    private static let errorText = Color(red: 139 / 255, green: 0, blue: 0)

    @State private var apiKey = "sk_sandbox_demo"
    @State private var client: DivergeClient?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diverge Sample")
                    .font(.largeTitle)
                    .foregroundColor(Self.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h1)

                Text("Enter a sandbox API key, then configure the SDK.")
                    .font(.body)
                    .foregroundColor(Self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Sandbox API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Sandbox API key")
                    .accessibilityHint("Demo key only. Do not use production secrets.")

                Button("Configure sandbox") {
                    configure()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityLabel("Configure sandbox")
                .accessibilityHint("Initializes the Diverge SDK with the sandbox environment")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(Self.errorText)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12))
                        .accessibilityLabel("Error: \(errorMessage)")
                        .accessibilityAddTraits(.updatesFrequently)
                }

                DivergeStatusView(client: client)
                    .background(Color(red: 0.97, green: 0.96, blue: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .dynamicTypeSize(.small ... .accessibility3)
    }

    private func configure() {
        do {
            client = try Diverge.configure(
                Configuration(apiKey: apiKey, environment: .sandbox)
            )
            errorMessage = nil
        } catch let error as DivergeError {
            client = nil
            errorMessage = error.errorDescription ?? "Configuration failed"
        } catch {
            client = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
