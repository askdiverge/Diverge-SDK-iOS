//
//  ChatView+ViewModel+Export.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// GDPR "Download my data" — writes the export to one protected temp file for the share sheet.
extension ChatView.ViewModel {

    /// Single temp path for the GDPR export. Overwritten on each download; deleted when
    /// Privacy dismisses or the share sheet completes.
    static let exportFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("diverge-export.json")

    /// Writes the GDPR export JSON to the stable temp file and returns its URL.
    /// Does not clear the conversation. A 401 surfaces as ``ChatView.SessionEnded``.
    func exportMyData() async throws -> URL {
        guard let provider = self.provider else { throw ChatView.ExportFailed() }
        do {
            let data = try await provider.exportMyData()
            guard
                let object = try? JSONSerialization.jsonObject(with: data),
                object is [String: Any]
            else {
                throw ChatView.ExportFailed()
            }
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtection)
#endif
            try data.write(to: Self.exportFileURL, options: options)
            return Self.exportFileURL
        } catch is ChatView.SessionEnded {
            throw ChatView.SessionEnded()
        } catch ChatServiceError.sessionExpired {
            throw ChatView.SessionEnded()
        } catch {
            throw ChatView.ExportFailed()
        }
    }

    /// Removes the temp export file so PII does not sit in the container after share / dismiss.
    func discardExportFile() {
        try? FileManager.default.removeItem(at: Self.exportFileURL)
    }
}
