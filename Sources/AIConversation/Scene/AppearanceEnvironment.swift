//
//  AppearanceEnvironment.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-24.
//

import SwiftUI

/// Environment value for the chat's display model, so views read the appearance without it
/// being threaded through every initialiser.
extension EnvironmentValues {
    var appearance: ChatAppearance {
        get { self[ChatAppearanceKey.self] }
        set { self[ChatAppearanceKey.self] = newValue }
    }
}

private struct ChatAppearanceKey: EnvironmentKey {
    static let defaultValue = ChatAppearance.default
}
