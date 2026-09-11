//
//  PrivacyExportLifecycle.swift
//  AIConversation
//

import Foundation

/// Owns the in-flight GDPR export `Task` so dismissing Privacy cannot present
/// a leftover share sheet on the next open.
@MainActor
final class PrivacyExportLifecycle {

    private var task: Task<Void, Never>?
    private(set) var isActive = false

    func start(_ work: @escaping @MainActor () async -> Void) {
        self.cancel()
        self.isActive = true
        self.task = Task { @MainActor in
            await work()
        }
    }

    func cancel() {
        self.isActive = false
        self.task?.cancel()
        self.task = nil
    }

    /// `nil` when Privacy was dismissed (or the task cancelled) before the GET returned.
    func shareFileIfActive(url: URL) -> ShareFile? {
        guard self.isActive, !Task.isCancelled else { return nil }
        return ShareFile(url: url)
    }
}
