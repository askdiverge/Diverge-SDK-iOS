//
//  ChatService+Requests.swift
//  AIConversationEngine
//

import Foundation
import AIConversationCore

extension ChatService {

    /// Messages per history page
    static let historyPageLimit = 100

    /// Every authenticated call identifies the calling SDK (platform + version) and lists the
    /// features it requests. The API major the client speaks is the `/api/v1/` path prefix.
    func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            Self.sdkPlatformHeader: Self.sdkPlatform,
            Self.sdkVersionHeader: self.sdkVersion,
            Self.clientProfileHeader: ClientProfile.headerValue(for: self.clientProfiles)
        ]
    }

    /// RAM-only by design: no disk cache, cookies, or credential storage
    /// conversation data and bearer tokens never persist.
    ///
    /// Session-level headers apply only when a request doesn't set the same
    /// header itself — the SSE request overrides `Accept` with `text/event-stream`.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        return URLSession(configuration: configuration)
    }

    /// Relative attachment paths in responses resolve against `baseURL`; see ``AttachmentURL``.
    static func decoder(baseURL: URL) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.userInfo[AttachmentURL.baseURLKey] = baseURL
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension ChatService {

    /// Dialoge API endpoints. Paths live here — the host may override `baseURL`.
    enum Endpoint: String {
        case config = "api/v1/chat/config"
        case messages = "api/v1/chat/messages"
        case actions = "api/v1/chat/actions"
        case forms = "api/v1/chat/forms"
        case session = "api/v1/chat/session"
        case livechatSync = "api/v1/chat/livechat/sync"
        case livechatHandover = "api/v1/chat/livechat/handover"
        case livechatMessages = "api/v1/chat/livechat/messages"
        case livechatTyping = "api/v1/chat/livechat/typing"
        case livechatClose = "api/v1/chat/livechat/close"
        case livechatFeedback = "api/v1/chat/livechat/feedback"
        case rate = "api/v1/chat/rate"
    }

    func url(for endpoint: Endpoint) -> URL {
        self.baseURL.appending(path: endpoint.rawValue)
    }
}

extension ChatService {

    /// Runs `work` and translates any lower-layer error into `ChatServiceError`.
    func mappingErrors<T: Sendable>(
        _ work: () async throws -> T
    ) async throws(ChatServiceError) -> T {
        do {
            return try await work()
        } catch {
            throw ChatServiceError(error)
        }
    }
}
