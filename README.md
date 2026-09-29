# Steady

A chat message list that loads older history at the top without shifting
what the user is reading.

**By Gaajar.** Started 21 September 2026.

## What it does

The hard part of a chat list is the prepend. Insert older messages above the
viewport in an ordinary list and everything the reader is looking at drops by
the height of the new rows. Steady avoids that structurally rather than by
correcting the offset afterwards: the collection view's content size is a
fixed canvas and never grows, so there is nothing for the scroll view to
adjust. Older messages get negative positions above an anchor, newer ones
positive positions below it, and the empty canvas on either side is hidden
with negative content insets. A page arriving changes one inset and nothing
else.

## What is in the package

| Type | Role |
|---|---|
| `ChatListViewController<Item>` | The list. Generic over any `Identifiable` item. |
| `Message` | A simple message value, if you do not have your own item type. |
| `Pager` | One direction of loading. Answers "may I load right now?" |

Cells, measurement and data loading are yours.

## Repository layout

| Path | What |
|---|---|
| `Package.swift`, `Sources/Steady/` | The package. |
| `Example/SteadyExample.xcodeproj` | A demo app that uses the package from this checkout. Work in progress. |
| `plan/` | Design notes. |

## Requirements

iOS 17 or later. Swift 5 language mode with default `MainActor` isolation, matching
the host app, so code moving across the boundary does not change meaning.

## Usage

```swift
import Steady

let list = ChatListViewController<Message>()

let registration = UICollectionView.CellRegistration<MyCell, Message> { cell, _, message in
    cell.configure(with: message)
}
list.cellProvider = { collectionView, indexPath, message in
    collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: message)
}
list.heightProvider = { message, width in
    // Height of the row at this width.
}
list.onNeedsOlder = { oldest in
    Task { list.prepend(await api.page(before: oldest.id)) }
}

list.setItems(await api.latest())       // first page, opens at the newest
list.append(newMessage)                 // one new message
```

