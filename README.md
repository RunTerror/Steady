# ChatList

A chat message list that loads older history at the top without shifting
what the user is reading.

**By Gaajar.** Started 21 September 2026.

## What it does

The hard part of a chat list is the prepend. Insert older messages above the
viewport in an ordinary list and everything the reader is looking at drops by
the height of the new rows. ChatList avoids that structurally rather than by
correcting the offset afterwards: the collection view's content size is a
fixed canvas and never grows, so there is nothing for the scroll view to
adjust. Older messages get negative positions above an anchor, newer ones
positive positions below it, and the empty canvas on either side is hidden
with negative content insets. A page arriving changes one inset and nothing
else.

## What is in the package today

| Type | Role |
|---|---|
| `Message` | The value a row shows. Server-issued id, stable across edits. |
| `Pager` | One direction of loading. Answers "may I load right now?" |
| `MessageRepository` | The seam. The list asks for pages; you decide where they come from. |

The UIKit layer (`ChatLayout`, `MessageCell`, `ChatViewController`) and the
SwiftUI composer still live in the host app and move here as the boundary is
worked out.

## Requirements

iOS 26. Swift 5 language mode with default `MainActor` isolation, matching
the host app, so code moving across the boundary does not change meaning.

## Usage

```swift
import ChatList

struct LiveRepository: MessageRepository {
    func latest(limit: Int) async -> [Message] { ... }
    func page(before cursor: Message.ID, limit: Int) async -> [Message] { ... }
}
```
