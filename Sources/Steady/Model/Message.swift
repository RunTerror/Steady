import Foundation

/// One chat message. `id` is a String because the server issues ids and
/// optimistic sends use a client-generated one that the server echoes back.
/// Hashable so the id can be used as a diffable data source item identifier
/// and the whole value can be compared during merges.
///
/// PACKAGING NOTES. Two things changed when this file crossed the boundary:
///
///   1. `public` on the type, on every property, and on the memberwise
///      init. Swift's default is `internal`, which means "visible inside
///      this module". Inside one app target everything is one module, so
///      you never notice. A package IS a separate module, so nothing is
///      visible until you say so. The compiler does not synthesize a
///      `public` memberwise init either: without the explicit one below,
///      the app could read a Message but never make one.
///
///   2. `nonisolated`. The package is built with default MainActor
///      isolation, same as the app, so `struct Message` alone would be a
///      main-actor type and its Hashable conformance would be main-actor
///      too. A plain value carrying no UI has no business being bound to
///      an actor, and diffable data sources require identifiers that are
///      safe on any thread. Same reason `Pager` and `Section` say it.
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
