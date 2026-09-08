import Foundation

/// POSTs `{"reset":true}` to the stand-in on `:3000` so each XCTest method starts from seed.
enum StandinControl {
    static func reset(timeout: TimeInterval = 2) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3000/__control")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"reset":true}"#.utf8)
        request.timeoutInterval = timeout
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + timeout)
    }
}
