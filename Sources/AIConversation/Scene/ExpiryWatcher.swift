//
//  ExpiryWatcher.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Flips `isExpired` the moment `expiry` passes while the view is on screen. Signed attachment
/// URLs carry a short TTL; without this a tile left open past it keeps its live look until some
/// unrelated re-render happens to re-evaluate `isExpired()`. Already-past expiries flip on appear.
struct ExpiryWatcher: ViewModifier {

    let expiry: Date?
    @Binding var isExpired: Bool

    func body(content: Content) -> some View {
        content.task(id: self.expiry) {
            guard let expiry = self.expiry else { return }
            let remaining = expiry.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            self.isExpired = true
        }
    }
}

extension View {

    /// Marks `isExpired` true once `expiry` has passed, live, for as long as the view is shown.
    func watchExpiry(_ expiry: Date?, isExpired: Binding<Bool>) -> some View {
        self.modifier(ExpiryWatcher(expiry: expiry, isExpired: isExpired))
    }
}
