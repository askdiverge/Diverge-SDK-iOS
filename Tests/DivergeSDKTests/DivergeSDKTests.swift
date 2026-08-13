import XCTest
@_spi(Testing) @testable import DivergeSDK

final class DivergeSDKTests: XCTestCase {
    override func tearDown() {
        Diverge.reset()
        super.tearDown()
    }

    func testVersionMatchesGeneratedConstant() {
        XCTAssertEqual(Diverge.version, VersionInfo.current)
    }

    func testVersionIsSemVerCore() {
        let pattern = #"^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"#
        XCTAssertNotNil(
            Diverge.version.range(of: pattern, options: .regularExpression),
            "Unexpected version string: \(Diverge.version)"
        )
    }

    func testConfigureRequiresNonEmptyAPIKey() {
        XCTAssertThrowsError(
            try Diverge.configure(Configuration(apiKey: "   ", environment: .sandbox))
        ) { error in
            XCTAssertEqual(error as? DivergeError, .invalidAPIKey)
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "API key must not be blank."
            )
        }
        XCTAssertFalse(Diverge.isConfigured)
    }

    func testConfigureSandboxClient() throws {
        let client = try Diverge.configure(
            Configuration(apiKey: "sk_test_123", environment: .sandbox)
        )
        XCTAssertTrue(Diverge.isConfigured)
        XCTAssertEqual(client.configuration.environment, .sandbox)
        XCTAssertEqual(client.apiBaseURL.absoluteString, "https://sandbox.api.askdiverge.ai")
        XCTAssertEqual(try Diverge.shared.configuration.apiKey, "sk_test_123")
    }

    func testConfigureProductionClient() throws {
        let client = try Diverge.configure(
            Configuration(apiKey: "sk_live_123", environment: .production)
        )
        XCTAssertEqual(client.configuration.environment, .production)
        XCTAssertEqual(client.apiBaseURL.absoluteString, "https://api.askdiverge.ai")
    }

    func testSharedThrowsWhenNotConfigured() {
        XCTAssertThrowsError(try Diverge.shared) { error in
            XCTAssertEqual(error as? DivergeError, .notConfigured)
        }
    }

    func testEnvironmentURLs() {
        XCTAssertEqual(
            Environment.sandbox.apiBaseURL.absoluteString,
            "https://sandbox.api.askdiverge.ai"
        )
        XCTAssertEqual(
            Environment.production.apiBaseURL.absoluteString,
            "https://api.askdiverge.ai"
        )
    }

    func testConfigurationDescriptionRedactsAPIKey() {
        let configuration = Configuration(apiKey: "sk_sandbox_secret_value", environment: .sandbox)
        let description = String(describing: configuration)
        XCTAssertFalse(description.contains("secret_value"))
        XCTAssertTrue(description.contains("sk_s…alue") || description.contains("…"))
        XCTAssertTrue(description.contains("sandbox"))
    }

    func testConcurrentConfigureAndShared() throws {
        let iterations = 50
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "diverge.concurrency", attributes: .concurrent)
        let failures = LockedCounter()

        for index in 0 ..< iterations {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    _ = try Diverge.configure(
                        Configuration(apiKey: "sk_concurrent_\(index)", environment: .sandbox)
                    )
                    _ = try Diverge.shared
                } catch {
                    failures.increment()
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(failures.value, 0)
        XCTAssertTrue(Diverge.isConfigured)
        XCTAssertNoThrow(try Diverge.shared)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
