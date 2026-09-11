//
//  PrivacyExportLifecycleTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

@Suite("Privacy export lifecycle")
@MainActor
struct PrivacyExportLifecycleTests {

    private let fileURL = URL(fileURLWithPath: "/tmp/diverge-export-test.json")

    @Test("shareFileIfActive returns a file while the session is active")
    func shareWhileActive() {
        let lifecycle = PrivacyExportLifecycle()
        lifecycle.start {}
        let file = lifecycle.shareFileIfActive(url: self.fileURL)
        #expect(file?.url == self.fileURL)
        lifecycle.cancel()
    }

    @Test("cancel drops a late share so the next Privacy open stays quiet")
    func cancelDropsLateShare() async {
        let lifecycle = PrivacyExportLifecycle()
        lifecycle.start {
            try? await Task.sleep(for: .milliseconds(40))
            #expect(lifecycle.shareFileIfActive(url: self.fileURL) == nil)
        }
        lifecycle.cancel()
        #expect(lifecycle.isActive == false)
        #expect(lifecycle.shareFileIfActive(url: self.fileURL) == nil)
        try? await Task.sleep(for: .milliseconds(60))
    }
}
