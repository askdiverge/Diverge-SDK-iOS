//
//  LivechatSession+Typing.swift
//  AIConversationEngine
//

import Foundation

extension LivechatSession {

    /// Asks for the agent to see `isTyping`. An expired session clears the state without posting,
    /// since its token no longer belongs to this visitor.
    func postTyping(_ isTyping: Bool) {
        guard !self.sessionExpired else {
            self.wantsTyping = false
            self.isTypingSent = false
            return
        }
        self.wantsTyping = isTyping
        guard self.typingPost == nil else { return }
        // Holds the session until the post settles, so "stopped typing" still reaches the agent
        // when the chat closes mid-burst.
        self.typingPost = Task { await self.sendTyping() }
    }

    /// Forgets the visitor's typing state without telling the agent: the session it belonged to
    /// is no longer active, and the backend clears the flag itself when a session closes or the
    /// visitor's data is deleted.
    func dropTyping() {
        self.typingIdleTask?.cancel()
        self.typingIdleTask = nil
        self.wantsTyping = false
        self.isTypingSent = false
        self.typingEpoch += 1
    }

    /// Posts the newest wanted typing state until the agent has it, while a session is active. A
    /// transient failure is retried after ``typingRetry``; after ``typingAttempts`` it stays unsent,
    /// and the next change tries again. A 401 ends the visitor session; any other refusal waits for
    /// the next change.
    func sendTyping() async {
        var failures = 0
        while self.wantsTyping != self.isTypingSent, !self.sessionExpired, self.lastStatus == .active {
            let isTyping = self.wantsTyping
            let gen = self.generation
            let epoch = self.typingEpoch
            do {
                try await self.service.sendLivechatTyping(isTyping: isTyping)
                guard epoch == self.typingEpoch else { break }
                self.isTypingSent = isTyping
                failures = 0
            } catch .sessionExpired {
                self.expire(generation: gen)
                break
            } catch let error where error.isTransient {
                failures += 1
                guard failures < Self.typingAttempts else { break }
                do {
                    try await self.sleep(Self.typingRetry)
                } catch {
                    break
                }
            } catch {
                break
            }
        }
        self.typingPost = nil
    }
}
