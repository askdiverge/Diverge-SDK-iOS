//
//  ListScrollViewResolver.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Finds the `UICollectionView` behind the `List` this view is a background of and reports a
/// closure that moves its content offset.
///
/// `List` ignores point-based `ScrollPosition` restores and quantises `scrollTo(_:anchor:)` to
/// three anchors, so adding the prepend's height to the offset directly is the only exact way to
/// keep the reader still when older history lands above them. Reports `nil` when no collection
/// view is found near this view — the caller then falls back to the anchor pin — and again with a
/// fresh closure whenever the view re-enters a window.
struct ListScrollViewResolver: UIViewRepresentable {

    let onResolve: @MainActor (((CGFloat) -> Void)?) -> Void

    func makeUIView(context: Context) -> ResolverView {
        ResolverView(onResolve: self.onResolve)
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {}

    final class ResolverView: UIView {

        private let onResolve: @MainActor (((CGFloat) -> Void)?) -> Void

        init(onResolve: @escaping @MainActor (((CGFloat) -> Void)?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
            self.isUserInteractionEnabled = false
            self.isAccessibilityElement = false
            self.accessibilityElementsHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// A background's platform view is attached before the list's own, so the first look on
        /// entering the window usually finds nothing; look again over the next few runloop turns.
        private static let retryDelays: [Duration] = [.zero, .milliseconds(50), .milliseconds(250), .seconds(1)]

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard self.window != nil else { return }
            self.resolve(attempt: 0)
        }

        private func resolve(attempt: Int) {
            guard self.window != nil else { return }
            if let collectionView = Self.collectionView(near: self) {
                self.onResolve { [weak collectionView] delta in collectionView?.contentOffset.y += delta }
                return
            }
            guard attempt + 1 < Self.retryDelays.count else {
                self.onResolve(nil)
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.retryDelays[attempt + 1])
                self?.resolve(attempt: attempt + 1)
            }
        }

        /// A SwiftUI background is hosted *beside* the list's own host view, not inside it, so the
        /// collection view is found by walking up a few ancestors and searching their subtrees.
        static func collectionView(near view: UIView) -> UICollectionView? {
            var ancestor = view.superview
            for _ in 0..<4 {
                guard let candidate = ancestor else { return nil }
                if let found = self.firstCollectionView(in: candidate) { return found }
                ancestor = candidate.superview
            }
            return nil
        }

        private static func firstCollectionView(in view: UIView) -> UICollectionView? {
            if let collectionView = view as? UICollectionView { return collectionView }
            for subview in view.subviews {
                if let found = self.firstCollectionView(in: subview) { return found }
            }
            return nil
        }
    }
}
#endif
