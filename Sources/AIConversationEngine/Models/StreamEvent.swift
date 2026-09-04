//
//  StreamEvent.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// Union of all SSE event types emitted during a message stream, decoded from the
/// NetworkManager envelope `{"type": "<sse event name>", "data": <frame data>}`.
///
/// Event flow: `status(connected)` → `status(processing)` → (`delta` | `part`)* → `done` | `error`.
/// `done` and `error` are terminal — the server closes the connection after sending them.
/// [API ref](https://docs.dialoge.ai/api#model/stream-event)
package enum StreamEvent: Decodable, Sendable, Equatable {

    /// Stream lifecycle state change.
    case status(Status)
    /// Incremental update to the in-progress part identified by `partId`.
    case delta(partId: String, PartDelta)
    /// A finalized part. Replaces any locally accumulated deltas for the same `part_id`.
    case part(Part)
    /// Terminal — the complete assistant message as persisted. Source of truth.
    case done(Message)
    /// Terminal — the stream failed. Disconnect after receiving.
    case error(Failure)
    /// Unrecognised SSE event name — skipped by the consumer.
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum Name: String, Decodable {
        case status
        case partDelta = "part_delta"
        case part
        case done
        case error
    }

    private struct DeltaEvent: Decodable {
        private let partId: String
        private let delta: PartDelta

        var event: StreamEvent {
            .delta(partId: self.partId, self.delta)
        }
    }

    private struct PartEvent: Decodable {
        let part: Part
    }

    private struct DoneEvent: Decodable {
        let message: Message
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container.decode(Name.self, forKey: .type) {
        case .status: .status(try container.decode(Status.self, forKey: .data))
        case .partDelta: try container.decode(DeltaEvent.self, forKey: .data).event
        case .part: .part(try container.decode(PartEvent.self, forKey: .data).part)
        case .done: .done(try container.decode(DoneEvent.self, forKey: .data).message)
        case .error: .error(try container.decode(Failure.self, forKey: .data))
        case .none: .unknown
        }
    }
}

extension StreamEvent {

    /// Stream lifecycle status event.
    /// [API ref](https://docs.dialoge.ai/api#model/stream-status-event)
    package struct Status: Decodable, Sendable, Equatable {

        package let state: State
        package let message: String?

        private enum CodingKeys: String, CodingKey {
            case state = "status"
            case message
        }

        package enum State: String, ExtendableEnum, Sendable {
            case connected
            case processing
            case complete
            case error
            case unknown
        }
    }

    /// Terminal stream error event.
    ///
    /// Stream errors are separate from HTTP-level failures — auth, validation,
    /// and rate-limit failures surface as non-2xx responses (`NetworkError.http`)
    /// before the SSE stream starts.
    /// [API ref](https://docs.dialoge.ai/api#model/stream-error-event)
    package struct Failure: Decodable, Sendable, Equatable {

        package let code: Code
        package let message: String
        package let retryable: Bool

        package enum Code: String, ExtendableEnum, Sendable {
            case generationFailed = "generation_failed"
            case unknown
        }
    }
}
