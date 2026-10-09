# Steady

**A chat list that holds still.**

<p align="center">
  <a href="docs/media/demo.mp4">
    <img src="docs/media/demo.webp" width="280" alt="Scrolling up through a chat in the example app. Older pages load above and the messages on screen do not move.">
  </a>
</p>

You're scrolling back through an old conversation, looking for the address
someone sent you in March. You find the right stretch, start reading, and the
screen lurches. The app has fetched another page of history and dropped it in
above you. The line you were reading is gone, somewhere below the fold.

Most chat apps handle this the same way: let the jump happen, then scroll back
before you notice. Usually you don't. Sometimes, mid-flick or when a bubble
resizes at the wrong moment, you do.

Steady doesn't fix the jump. It never lets it happen.

<p align="center">
  <img src="docs/media/the-jump.svg" width="100%" alt="Animation. In most lists, an older page slams in at the top and shoves the message you are reading off screen, and a face turns dizzy. In Steady, the page lands above the screen, nothing moves, and the face sips tea.">
</p>

## The trick

Picture the conversation pinned to a wall a million points tall. It starts in
the middle, and the wall never gets any taller. Older messages are pinned
above, newer ones below, always on bare wall that was already there. A curtain
hides the empty stretches, so you can't scroll into nothing.

When history arrives, Steady pins it above the first message and draws the
curtain back a little. Nothing already on the wall moves, so nothing on your
screen does either.

<sub>For the UIKit-minded: `contentSize` is constant, older rows take negative
offsets from an anchor at the midpoint, negative `contentInset`s are the
curtain, and a prepend touches only `contentInset.top`. `contentOffset` is
never written. See [`ChatLayout.swift`](Sources/Steady/Layout/ChatLayout.swift).</sub>

<a href="docs/prepend-jump.html#virtual/0">
  <img src="docs/media/prepend-jump-steps.gif" width="100%" alt="A slideshow of one insertion. In a plain ScrollView, msg-0 moves 240 points down the screen. In Steady, the new rows land above and msg-0 moves 0 points.">
</a>

Keep an eye on *msg-0 moved on screen*. A plain list shifts it 240 points;
Steady, not at all. [Step through it yourself](docs/prepend-jump.html).

## Installing it

In Xcode, choose **File › Add Package Dependencies** and paste
`https://github.com/RunTerror/Steady.git`. Or add it to `Package.swift`:

```swift
.package(url: "https://github.com/RunTerror/Steady.git", from: "0.1.0")
```

Steady is at 0.1, an early release. It's ready to try; expect the API to
shift a little before 1.0.

## Using it

You bring the cells, their heights and the history. Steady decides where
everything goes.

```swift
import Steady

let list = ChatListViewController<Message>()

list.cellProvider = { collectionView, indexPath, message in
    collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: message)
}
list.heightProvider = { message, width in
    MessageCell.height(for: message, width: width)
}
list.onNeedsOlder = { oldest in
    Task { list.prepend(await api.page(before: oldest.id)) }
}

list.setItems(await api.latest())
```

<details>
<summary>Every setting</summary>

<br>

| Property | Purpose |
|---|---|
| `cellProvider` | The cell for an item. |
| `heightProvider` | An item's height at a given width, cached per item. |
| `onNeedsOlder` | Called as the reader nears the top. Answer with `prepend(_:)`; an empty page means history has run out. |
| `contextMenuProvider` | The long-press menu for an item, or `nil`. |
| `topInset`, `bottomInset` | Breathing room above the first item and below the last. |
| `loadingView` | Shown until the first page lands. |
| `showsScrollIndicator` | Off by default. |
| `prefetchFraction` | How early loading starts, from 0 (top) to 1. Defaults to 0.25. |

| Method | Use |
|---|---|
| `setItems(_:)` | The first page. Opens at the newest item. |
| `prepend(_:)` | An older page. Messages already in the list are skipped, so overlapping pages are fine. |
| `append(_:from:)` | A new message, optionally flying in from the composer. If its id is already in the list, say a sent message echoed back, it's updated in place. |

A cell that adopts `ChatContextMenuPreviewing` can hand the context menu just
its bubble to lift, instead of the whole row.

</details>

## Try it

Open [`Example/`](Example/), run it, and pick a message. Scroll up slowly.
Pages arrive above it, one after another, and it doesn't flinch.

## Fine print

- **The wall is big, not endless.** About five thousand messages each way from
  where you start.
- **Heights come from you, not Auto Layout.** That's what makes placement
  exact. Keep the height function beside the cell so the two never disagree.
- **The scroll bar only knows what's loaded,** so it drifts as history arrives.
  It's off by default for that reason.
- **Not yet:** deleting messages, edits that change a message's height,
  reacting to a change in text size, and a way to report a page that failed to
  load.

---

<sub>iOS 17 or later · Swift 5 language mode, `MainActor` by default · [MIT licence](LICENSE) · Written by Gaajar, begun 21 September 2026</sub>
