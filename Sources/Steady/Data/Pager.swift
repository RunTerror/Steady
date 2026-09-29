//
//  Pager.swift
//  Steady
//
//  Created by Gaajar on 15/09/26.
//

import Foundation

/// Tracks one direction of loading. Guarantees only one request is in
/// flight at a time, and that nothing more is asked for once a page comes
/// back empty.
///
///     idle ──beginLoading()──▶ loading ──finish(n > 0)──▶ idle
///                                 ├──────finish(0)──────▶ exhausted
///                                 └──────fail()─────────▶ failed ──beginLoading()──▶ loading
public nonisolated struct Pager {
    public enum State { case idle, loading, exhausted, failed }

    public private(set) var state: State = .idle

    public init() {}

    /// True when a load may start: idle or failed.
    public var canLoad: Bool {
        switch state {
        case .idle, .failed: return true
        default: return false
        }
    }

    /// Moves to `.loading` and returns true, or returns false and does
    /// nothing if a load may not start.
    public mutating func beginLoading() -> Bool {
        guard canLoad else {
            return false
        }
        state = .loading
        return true
    }

    /// Back to `.idle`, or `.exhausted` if the page was empty.
    public mutating func finish(receivedCount: Int) {
        if receivedCount == 0 {
            state = .exhausted
        } else {
            state = .idle
        }
    }

    /// Moves to `.failed`. A later `beginLoading()` is allowed again.
    public mutating func fail() {
        state = .failed
    }
}
