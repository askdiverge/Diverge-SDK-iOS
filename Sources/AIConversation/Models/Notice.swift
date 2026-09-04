//
//  Notice.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

/// A transient notice: its edge, message, and auto-dismiss policy.
struct Notice: Equatable {

    enum Edge {
        case top
        case bottom
    }

    let edge: Edge
    let message: String

    /// Delay after which it should auto-dismiss; `nil` to persist until cleared.
    let autoDismiss: Duration?
}
