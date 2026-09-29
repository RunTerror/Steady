import Foundation

// STEP 2: Pager state machine. You write this one.
//
// A pager tracks one direction of loading (older, for now) and guarantees
// two things:
//
//   1. Only one request is in flight at a time. scrollViewDidScroll fires
//      sixty times a second near the top; without this guard you would
//      start sixty loads.
//   2. Once a page comes back empty, we never ask again.
//
// From the plan:
//
//   idle ──load()──▶ loading ──success(page)──▶ idle (or exhausted if page.isEmpty)
//                      └────failure────────▶ failed ──retry()──▶ loading
//
// Suggested shape (a struct with an enum inside is enough):
//
public nonisolated struct Pager {
    public enum State { case idle, loading, exhausted, failed }

    /// `public private(set)`: everyone can read the state, only the methods
    /// below can change it. That is the whole guarantee of a state machine,
    /// and it is the access control that enforces it across the boundary.
    public private(set) var state: State = .idle

    /// A struct's memberwise init is internal even when the struct is
    /// public, so a package type you want callers to create needs one of
    /// these written out.
    public init() {}

       /// True when a load may start: idle or failed. Never loading or exhausted.
    public var canLoad: Bool {
        switch state {
        case .idle, .failed: return true
        default: return false
        }
    }

       /// Move to .loading. Returns false and does nothing if !canLoad.
       /// The caller uses the Bool to decide whether to actually fetch.
    public mutating func beginLoading() -> Bool {
        guard canLoad else {
            return false
        }
        state = .loading
        return true
    }

       /// Back to .idle, or .exhausted if the page was empty.
    public mutating func finish(receivedCount: Int) {
        if receivedCount == 0 {
            state = .exhausted
        } else {
            state = .idle
        }
    }

       /// To .failed. A later beginLoading() is allowed again.
    public mutating func fail() {
        state = .failed
    }
}
//
// Keep it free of UIKit and free of async. It is a value that answers
// "may I load right now?" and nothing else, which is what makes it easy
// to unit test. Write three tests: a second beginLoading while loading
// returns false; finish(receivedCount: 0) makes canLoad false forever;
// fail() then beginLoading() returns true.
