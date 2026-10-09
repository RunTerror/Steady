# Steady

**A chat list for iOS that keeps your messages exactly where they are.**

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

<p align="center">
  <a href="docs/media/demo.mp4">
    <img src="docs/media/demo.webp" width="320" alt="Scrolling through a chat while older messages load without moving the visible content">
  </a>
</p>

## The problem

You're reading an old message. You scroll up, another page loads, and suddenly the message you're looking at has moved.

Most chat lists work around this by adjusting the scroll position after inserting older messages. It usually works, but the list can still jump when cells resize, images load, or the user scrolls quickly.

**Steady takes a different approach: older messages are inserted without changing the position of anything already on screen.**

No scroll-offset corrections. No visible jumps.

## How it works

Steady uses a fixed coordinate space instead of growing the scrollable content every time a page arrives.

- **Fixed content size:** The underlying scroll view doesn't grow as messages load.
- **Stable message positions:** Older messages occupy unused space above the existing content.
- **No offset adjustments:** Prepending a page never requires writing to `contentOffset`.
- **Lazy history loading:** Your data source fetches older messages as the user approaches the beginning of the loaded history.

The implementation uses a central anchor, negative item coordinates, and adjusted content insets to keep the visible region stable.

See [`ChatLayout.swift`](Sources/Steady/Layout/ChatLayout.swift) for the implementation.

<p align="center">
  <img src="docs/media/the-wall.svg" width="100%" alt="Older messages are added above the visible region while existing messages remain stationary">
</p>

## Installation

Add Steady through Xcode:

1. Open **File → Add Package Dependencies**.
2. Enter `https://github.com/RunTerror/Steady.git`.
3. Select the version you want.

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/RunTerror/Steady.git",
        from: "0.1.0"
    )
]
```

## Usage

Steady handles the layout and scroll-position stability. You provide the message cells, their heights, and the pagination callback.

```swift
import Steady

let chat = ChatListViewController<Message>()

chat.cellProvider = { collectionView, indexPath, message in
    collectionView.dequeueConfiguredReusableCell(
        using: registration,
        for: indexPath,
        item: message
    )
}

chat.heightProvider = { message, width in
    MessageCell.height(for: message, width: width)
}

chat.onNeedsOlder = { oldestMessage in
    Task { @MainActor in
        let olderMessages = await api.page(
            before: oldestMessage.id
        )
        chat.prepend(olderMessages)
    }
}

chat.setItems(await api.latest())
```

The list opens at the newest message. As the user scrolls back, Steady requests older pages and inserts them without moving the visible messages.

For SwiftUI, wrap `ChatListViewController` in `UIViewControllerRepresentable`. See the [example implementation](Example/SteadyExample/Chat/ChatListView.swift).

## API

| API | Purpose |
|---|---|
| `setItems(_:)` | Load the initial messages and open at the newest one. |
| `prepend(_:)` | Insert older messages without shifting visible content. |
| `append(_:from:)` | Append a new message, optionally animating it from the composer. |
| `cellProvider` | Configure reusable message cells. |
| `heightProvider` | Provide the height of a message for a given width. |
| `onNeedsOlder` | Fetch another page when the user approaches the top. |
| `contextMenuProvider` | Customize long-press context menus. |

Additional configuration includes top and bottom insets, a loading view, scroll-indicator visibility, and the history-prefetch threshold.

See the example app for the complete API in action.

## Limitations

Steady is an early release. Here's what to know before using it in production:

- **Finite coordinate space:** Supports approximately 5,000 messages in either direction from the initial position.
- **Explicit cell heights:** Your height provider must agree with the rendered cell's actual height.
- **Scrollbar accuracy:** The scroll indicator reflects loaded content rather than the entire conversation history.
- **Incomplete update handling:** Message deletion, height-changing edits, dynamic text-size changes, and pagination-error handling are not implemented yet.

The current release is intended for experimentation and feedback. See the [open issues](https://github.com/RunTerror/Steady/issues) for ongoing work.

## Example

Run the app in [`Example/`](Example/) to see Steady in action. Scroll through a conversation while older pages load, and watch the visible messages stay put.

## Contributing

Bug reports, ideas, and pull requests are welcome.

- [Open an issue](https://github.com/RunTerror/Steady/issues)
- [Star the repository](https://github.com/RunTerror/Steady/stargazers)

If you've built a chat interface on iOS, feedback on the layout approach and its edge cases would be especially useful.

---

Made by Gaajar · iOS 17+ · MIT License
