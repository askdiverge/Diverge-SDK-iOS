//
//  Paginator.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-11.
//

import Foundation

/// Single-flight cursor pagination for conversation history.
///
/// Owns the opaque history cursor and the load lifecycle. `next()` hands out the
/// cursor for the upcoming page and locks the paginator; the caller then `commit`s
/// the page's `nextCursor` on success, or `release`s it on failure — which keeps the
/// current cursor so the same page can be retried. A second `next()` while a load is
/// in flight throws `.busy`, so spamming pull-to-refresh can't fire overlapping
/// history calls or queue them up.
struct Paginator {

    private var cursor: String?
    private(set) var isExhausted = false
    private var isLoading = false

    /// Cursor for the next page, locking the paginator until `commit`/`release`.
    /// `nil` is a valid cursor — it requests the first (newest) page.
    /// Throws `.busy` if a load is already in flight, `.exhausted` if no pages remain.
    mutating func next() throws(Failure) -> String? {
        guard !self.isLoading else { throw .busy }
        guard !self.isExhausted else { throw .exhausted }
        self.isLoading = true
        return self.cursor
    }

    /// Records a successful load: stores the page's `nextCursor` (a `nil` cursor ends
    /// pagination) and unlocks.
    mutating func commit(nextCursor: String?) {
        self.cursor = nextCursor
        self.isExhausted = nextCursor == nil
        self.isLoading = false
    }

    /// Records a failed load: unlocks without advancing, so the same cursor retries.
    mutating func release() {
        self.isLoading = false
    }
}

extension Paginator {

    enum Failure: Error {
        /// A page load is already in flight.
        case busy
        /// No more pages — the last page returned no cursor.
        case exhausted
    }
}
