import Foundation

/// Host-side session rotation for the Sample.
///
/// `POST /api/v1/chat/auth/reset` needs the chatbot API key (Basic auth) plus the
/// current visitor JWT. The key is never baked into the app — pass
/// `SAMPLE_CHATBOT_API_KEY` at launch. Stand-in UITests keep the in-memory
/// `/__control` wipe and reuse the same token.
enum SampleVisitorReset {

    enum Failure: Error {
        case missingAPIKey
        case invalidResponse
    }

    static func freshToken(currentVisitorToken: String, apiBaseURL: URL) async throws -> String {
        let env = ProcessInfo.processInfo.environment
        if env["SAMPLE_STANDIN"] == "1" {
            var request = URLRequest(url: apiBaseURL.appendingPathComponent("__control"))
            request.httpMethod = "POST"
            request.httpBody = Data(#"{"reset":true}"#.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await URLSession.shared.data(for: request)
            return currentVisitorToken
        }

        guard let apiKey = env["SAMPLE_CHATBOT_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw Failure.missingAPIKey
        }

        var request = URLRequest(url: apiBaseURL.appending(path: "api/v1/chat/auth/reset"))
        request.httpMethod = "POST"
        let basic = Data("\(apiKey):".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["visitor_token": currentVisitorToken]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["token"] as? String,
              !newToken.isEmpty
        else {
            throw Failure.invalidResponse
        }
        return newToken
    }
}
