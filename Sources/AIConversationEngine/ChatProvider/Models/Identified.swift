//
//  Identified.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-03.
//

import Foundation

/// Pairs a model with a client-minted stable identity.
package struct Identified<Model: Sendable & Equatable>: Identifiable, Sendable, Equatable {
    package let id: UUID
    package let model: Model

    package init(id: UUID = UUID(), model: Model) {
        self.id = id
        self.model = model
    }
}
