//
//  ScrollTaskBox.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-19.
//

import SwiftUI

/// Holds the pending scroll `Task` off of `@State`. The task is a side-effect handle, not view state, so
/// cancelling and replacing it on each scroll request must not invalidate the view a reference held in
/// `@State` mutates without notifying SwiftUI.
@MainActor
final class ScrollTaskBox {

    private var task: Task<Void, Never>?

    /// Cancels any in-flight scroll and adopts the new one — coalesces a burst into the last request.
    func replace(with task: Task<Void, Never>) {
        self.task?.cancel()
        self.task = task
    }

    /// Returns to `id` at the top of the view once the layout that moved it has committed.
    func land(on id: UUID, proxy: ScrollViewProxy) {
        self.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            proxy.scrollTo(id, anchor: .top)
        })
    }
}
