//
//  URLRequest+EndpointMethod.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

extension URLRequest {
    enum EndpointMethod: String {
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    init(url: URL, method: EndpointMethod, headers: [String: String]?) {
        self.init(url: url)
        self.httpMethod = method.rawValue
        self.allHTTPHeaderFields = headers
    }
}
