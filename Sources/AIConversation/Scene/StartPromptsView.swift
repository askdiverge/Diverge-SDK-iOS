//
//  StartPromptsView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Wrapping outlined capsule chips for config `start_prompts`. Tap sends `promptText`
/// as a normal user message via `onSelect`. Identity is the chip index — the wire
/// model has no id, and duplicate `prompt_text` rows must stay distinct.
struct StartPromptsView: View {

    @Environment(\.appearance) private var appearance

    let prompts: [StartPrompt]
    let onSelect: (String) -> Void

    var body: some View {
        OutlinedChipFlow(
            labels: self.prompts.map(\.promptText),
            accessibilityPrefix: "startPrompt",
            onSelect: self.onSelect
        )
        .padding(.top, self.appearance.spacing.units(2))
    }
}
