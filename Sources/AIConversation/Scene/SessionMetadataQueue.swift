//
//  SessionMetadataQueue.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Holds the metadata the host sets through ``AIChat/setMetadata(_:)`` and
/// ``AIChat/setSignedMetadata(_:)`` until a chat is on screen with a session, then sends it one
/// patch at a time, as the web widget does. What waits is kept to what the session needs: unsigned
/// calls merged into one patch by the backend's own rule, which the backend accepts or refuses as
/// one, and the newest signed token. A patch that fails for a reason that may pass (the
/// connection, a timeout, a 5xx) stays queued and goes again on the next call, the next send or
/// the next time a chat is shown; one the backend answers with any other 4xx, a 401 included, is
/// dropped.
///
/// ``AIChat`` holds it, because each presentation builds a new view model. It lives in memory for
/// as long as its holder: one `AIChat`, or the shared configuration for instances minted from it.
@MainActor
final class SessionMetadataQueue {

    /// Sends one patch to the visitor's session.
    typealias Patcher = @Sendable (SessionMetadataPatchRequest) async throws -> Void

    private var pending: [SessionMetadataPatchRequest] = []
    /// The chat on screen with a session, and how to send through it. A chat that leaves the
    /// screen, or goes away, takes its session with it.
    private weak var chat: AnyObject?
    private var patcher: Patcher?
    private var delivery: Task<Void, Never>?
    /// Bumped when the chat to send through changes, so a delivery that began before it leaves
    /// the queue alone.
    private var epoch = 0

    /// Queues `patch` and sends it when a chat is attached. Unsigned metadata merges into the
    /// unsigned patch still waiting, where the two can go as one. A signed token replaces the
    /// token still waiting: the backend takes the newest token as the visitor's current claims, and
    /// an older one may belong to a customer who has since logged out.
    func enqueue(_ patch: SessionMetadataPatchRequest) {
        // The first patch is on its way while a delivery runs; the rest are still ours to change.
        let sending = self.pending.prefix(self.delivery == nil ? 0 : 1)
        var waiting = Array(self.pending.dropFirst(sending.count))
        if patch.signedMetadata != nil {
            waiting.removeAll { $0.signedMetadata != nil }
            waiting.append(patch)
        } else if let index = waiting.lastIndex(where: { $0.signedMetadata == nil }),
                  let merged = waiting[index].merging(patch) {
            waiting[index] = merged
        } else {
            waiting.append(patch)
        }
        self.pending = sending + waiting
        self.deliver()
    }

    /// Sends through `patcher` from now on: `chat` is on screen with a session. Also sends what an
    /// earlier failure left queued. A delivery through another chat stops, and its patch goes
    /// again through this one.
    func attach(_ patcher: @escaping Patcher, for chat: AnyObject) {
        if self.chat !== chat { self.stopDelivery() }
        self.chat = chat
        self.patcher = patcher
        self.deliver()
    }

    /// Stops sending through `chat`, which left the screen or is deleting the visitor's data.
    /// What is queued, the patch on its way included, waits for the next chat.
    func detach(_ chat: AnyObject) {
        guard self.chat === chat else { return }
        self.chat = nil
        self.patcher = nil
        self.stopDelivery()
    }

    /// Drops everything queued and detaches the chat, when the visitor's data is deleted.
    func clear() {
        self.pending = []
        self.chat = nil
        self.patcher = nil
        self.stopDelivery()
    }
}

// MARK: - Delivery

private extension SessionMetadataQueue {

    func deliver() {
        guard self.delivery == nil, self.chat != nil, let patcher = self.patcher, !self.pending.isEmpty else {
            return
        }
        let epoch = self.epoch
        self.delivery = Task { await self.drain(through: patcher, epoch: epoch) }
    }

    func stopDelivery() {
        self.epoch += 1
        self.delivery?.cancel()
        self.delivery = nil
    }

    func drain(through patcher: Patcher, epoch: Int) async {
        while epoch == self.epoch, let patch = self.pending.first {
            let sent = await Self.send(patch, through: patcher)
            guard epoch == self.epoch else { return }
            guard sent else { break }
            self.pending.removeFirst()
        }
        guard epoch == self.epoch else { return }
        self.delivery = nil
    }

    /// Whether `patch` is done with: sent, or refused for good. `false` keeps it queued.
    static func send(_ patch: SessionMetadataPatchRequest, through patcher: Patcher) async -> Bool {
        do {
            try await patcher(patch)
            return true
        } catch {
            return !ChatServiceError(error).isTransient
        }
    }
}

// MARK: - Merging

private extension SessionMetadataPatchRequest {

    /// This patch and `next` as one, when both carry unsigned metadata and the backend stores the
    /// same from the one as from the two in turn; `nil` when they go separately.
    func merging(_ next: Self) -> Self? {
        guard self.signedMetadata == nil, next.signedMetadata == nil,
              let current = self.metadata, let patch = next.metadata,
              let merged = current.merging(patch) else { return nil }
        return .init(metadata: merged, signedMetadata: nil)
    }
}

private extension [String: JSONValue] {

    /// `patch` over these values by the backend's rule: an object merges into the object under
    /// the same key, and any other value replaces what is there. `nil` when `patch` puts an
    /// object over a value of another kind: sent in turn, the backend replaces whatever object
    /// the session holds under that key, and sent as one it would merge into it.
    func merging(_ patch: [String: JSONValue]) -> [String: JSONValue]? {
        var merged = self
        for (key, value) in patch {
            switch (merged[key], value) {
            case (.object(let current), .object(let next)):
                guard let inner = current.merging(next) else { return nil }
                merged[key] = .object(inner)
            case (.some, .object):
                return nil
            default:
                merged[key] = value
            }
        }
        return merged
    }
}
