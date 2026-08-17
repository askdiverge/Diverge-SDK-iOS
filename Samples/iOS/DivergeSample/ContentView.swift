import DivergeSDK
import DivergeSDKUI
import SwiftUI

struct ContentView: View {
    @State private var apiKey = "sk_sandbox_demo"
    @State private var client: DivergeClient?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diverge Sample")
                    .font(.largeTitle)
                    .foregroundColor(Color.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter a sandbox API key, then configure the SDK.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Sandbox API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
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
                        .foregroundColor(Color.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12))
                        .accessibilityLabel("Error: \(errorMessage)")
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
