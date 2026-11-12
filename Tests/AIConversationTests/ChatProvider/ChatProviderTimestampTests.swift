//
//  ChatProviderTimestampTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — message timestamps")
struct ChatProviderTimestampTests {

    @Test(
        "the timestamp forms the backend sends read as the same instant, in milliseconds",
        arguments: [
            "2026-11-11T15:34:40.949Z",
            "2026-11-11T15:34:40.94912+00:00",
            "2026-11-11T15:34:40.949123+00:00",
            "2026-11-11T17:34:40.949+02:00"
        ]
    )
    func backendForms(timestamp: String) {
        #expect(ChatProvider.milliseconds(of: timestamp) == 1_794_411_280_949)
    }

    @Test("a timestamp without fractional seconds reads at the whole second")
    func wholeSeconds() {
        #expect(ChatProvider.milliseconds(of: "2026-11-11T15:34:40Z") == 1_794_411_280_000)
    }

    @Test("a timestamp that doesn't parse has no place in the order", arguments: ["", "yesterday", "2026-11-11"])
    func unreadable(timestamp: String) {
        #expect(ChatProvider.milliseconds(of: timestamp) == nil)
    }
}
