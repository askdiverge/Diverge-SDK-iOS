//
//  NewestTurnRest.swift
//  AIConversation
//

/// Tracks whether the top-flowing list rests on its newest turn, and decides whether bot content
/// that arrives there is scrolled into view.
///
/// The list rests on its newest turn from the moment it opens. The reader dragging it, asking for
/// earlier turns, or a reply growing past them takes it off; a scroll that comes to rest sets it
/// from where it ended. It is a reference held in `@State`, like ``ScrollTaskBox``, so the scroll
/// callbacks that write it leave the view as it is.
@MainActor
final class NewestTurnRest {

    private(set) var isResting = true

    /// The reader started dragging the list.
    func readerScrolled() {
        self.isResting = false
    }

    /// A scroll came to rest, on the newest turn or away from it.
    func scrollEnded(onNewestTurn: Bool) {
        self.isResting = onNewestTurn
    }

    /// The reader asked for earlier turns, and the list stays with the turn they asked from.
    func askedForEarlierTurns() {
        self.isResting = false
    }

    /// A streaming reply grew. With its user turn held at the top the exchange places the list.
    /// Otherwise the reply can grow past the screen with nothing following it, so the list is
    /// off its rest until a scroll ends on the newest turn.
    func replyGrew(heldByExchange: Bool) {
        if !heldByExchange { self.isResting = false }
    }

    /// Whether the list scrolls to the newest turn for bot content that arrived outside a
    /// streaming reply. It does while it rests there with nothing else placing it: an exchange
    /// holding its user turn at the top places the list itself, content that arrives while an
    /// exchange's buffer remains lands in that buffer, and a reader in a form field keeps their
    /// place.
    func follows(holdsExchange: Bool, bufferRemains: Bool, isEditingForm: Bool) -> Bool {
        self.isResting && !holdsExchange && !bufferRemains && !isEditingForm
    }
}
