//
//  SubmittedFormStore.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Remembers which form `part_id`s this device has already submitted, and the confirmation
/// shown for each, so a relaunch renders the collapsed confirmation instead of a fillable form.
///
/// The server records nothing on the conversation after `POST /actions` and accepts repeat
/// submissions, so without this a visitor could file the same lead or ticket twice. Part ids
/// are `part_<uuid>` — globally unique — so one flat map is enough.
///
/// Stored as a small JSON file under Application Support (not `UserDefaults`, which the
/// privacy manifest declares unused). Bounded to ``maxEntries`` so it cannot grow without end.
final class SubmittedFormStore: @unchecked Sendable {

    /// Oldest entries are dropped past this many.
    static let maxEntries = 200

    private let fileURL: URL?
    private let lock = NSLock()
    private var entries: [Entry]

    private struct Entry: Codable, Equatable {
        let partId: String
        let confirmation: String
    }

    /// Default location: `Application Support/AIConversation/forms/submitted.json`.
    convenience init() {
        self.init(fileURL: Self.defaultFileURL())
    }

    /// Explicit location — tests point this at a temporary directory. `nil` keeps the store in
    /// memory only.
    init(fileURL: URL?) {
        self.fileURL = fileURL
        self.entries = Self.load(from: fileURL)
    }

    /// The confirmation recorded for `partId`, or `nil` if it was never submitted here.
    func confirmation(for partId: String) -> String? {
        self.lock.withLock {
            self.entries.last { $0.partId == partId }?.confirmation
        }
    }

    /// Records a successful submission (replacing any earlier record for the same id).
    func record(partId: String, confirmation: String) {
        self.lock.withLock {
            self.entries.removeAll { $0.partId == partId }
            self.entries.append(Entry(partId: partId, confirmation: confirmation))
            if self.entries.count > Self.maxEntries {
                self.entries.removeFirst(self.entries.count - Self.maxEntries)
            }
            self.persist()
        }
    }

    /// Forgets everything — part of visitor data deletion.
    func removeAll() {
        self.lock.withLock {
            self.entries = []
            if let url = self.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Disk

    private func persist() {
        guard let url = self.fileURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(self.entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL?) -> [Entry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else {
            return nil
        }
        return support
            .appendingPathComponent("AIConversation/forms", isDirectory: true)
            .appendingPathComponent("submitted.json")
    }
}
