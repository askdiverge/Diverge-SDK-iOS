//
//  ColorHexTests.swift
//  AIConversationTests
//

import SwiftUI
import Testing
@testable import AIConversation

@Suite("Color(css:)")
struct ColorHexTests {

    @Test("hex shorthand and long forms parse")
    func hex() {
        #expect(Color(css: "#F00") != nil)
        #expect(Color(css: "#112233") != nil)
        #expect(Color(css: "#11223344") != nil)
    }

    @Test("rgb and rgba functional forms parse")
    func functional() {
        #expect(Color(css: "rgb(255, 0, 0)") != nil)
        #expect(Color(css: "rgba(0, 128, 0, 0.5)") != nil)
        #expect(Color(css: "rgb(100%, 0%, 0%)") != nil)
    }

    @Test("junk returns nil")
    func junk() {
        #expect(Color(css: "not-a-color") == nil)
        #expect(Color(css: "rgb(1, 2)") == nil)
    }
}
