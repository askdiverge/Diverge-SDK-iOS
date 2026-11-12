//
//  ImageUploadPromptAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

/// Pins the VoiceOver contract of the upload-prompt card: what is spoken as the label and hint.
/// The `.isButton` trait comes from wrapping the card in `Button`, which is structural.
@Suite("ImageUploadPromptView — accessibility contract")
struct ImageUploadPromptAccessibilityTests {

    /// Under `xcodebuild test` (CI) the catalog is compiled and this resolves to copy; under the
    /// `swift test` CLI String Catalogs are not compiled and every key echoes itself. Assert only
    /// what holds on both runners: the label and hint are wired to non-empty resources.
    @Test("label is wired to a non-empty string resource")
    func labelIsWired() {
        #expect(!ImageUploadPromptView.accessibilityLabel.isEmpty)
    }

    @Test("hint is wired to a non-empty string resource")
    func hintIsWired() {
        #expect(!ImageUploadPromptView.accessibilityHint.isEmpty)
    }
}
