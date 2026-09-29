//
//  Message.swift
//  Steady
//
//  Created by Gaajar on 15/09/26.
//

import Foundation

/// One chat message. `id` is a String because the server issues ids, and an
/// optimistic send uses a client-generated one that the server echoes back.
public nonisolated struct Message: Identifiable, Hashable, Sendable {
    public let id: String
    public let message: String
    public let isMe: Bool

    public init(id: String, message: String, isMe: Bool) {
        self.id = id
        self.message = message
        self.isMe = isMe
    }
}
