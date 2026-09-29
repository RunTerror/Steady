//
//  ChatLayout.swift
//  Steady
//
//  Created by Gaajar on 21/09/26.
//

import UIKit

/// Layout for `ChatListViewController`.
///
/// The content size never changes: it is a fixed 1,000,000 pt canvas with
/// the first item at its middle (`anchorY`). Older items are placed above the
/// anchor with negative `y`, newer ones below. The empty canvas on either side
/// is hidden with negative content insets (`hidingInsets`). Because
/// contentSize never grows and contentOffset is never touched, a prepend
/// cannot move what the user is reading.
///
///     canvas y                                   Metric.y
///     0          ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
///                :  empty, hidden by        :   older rows grow up
///                :  contentInset.top < 0    :   into here (y < 0)
///     anchorY    ├──────────────────────────┤  0
///                │ row 0                    │
///                ├──────────────────────────┤
///                │ ...                      │
///                ├──────────────────────────┤  last.maxY
///                :  empty, hidden by        :   newer rows grow down
///                :  contentInset.bottom < 0 :   into here
///     1,000,000  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
///
/// Not supported yet: deletes, and edits that change a row's height.
final class ChatLayout: UICollectionViewLayout {

    static let canvasHeight: CGFloat = 1_000_000
    static let anchorY: CGFloat = canvasHeight / 2

    /// Where one item is, relative to the anchor.
    struct Metric {
        var y: CGFloat
        var height: CGFloat
        var maxY: CGFloat {
            get {
                y + height
            }
        }
    }

    /// One entry per item in section 0, in item order.
    private(set) var metrics: [Metric] = []

    /// Height of item `index` at `width`. Supplied by the controller.
    var heightForItem: ((_ index: Int, _ width: CGFloat) -> CGFloat)?

    /// Used when `heightForItem` is not set.
    var fallbackHeight: CGFloat = 80

    /// Width the metrics were measured at. Text rewraps at a new width, so a
    /// change means every height must be measured again.
    private var metricsWidth: CGFloat = 0

    /// Where a row inserted by the next animated batch update starts its
    /// animation, in content coordinates. Cleared when the batch finishes.
    var appearFromFrame: CGRect?

    /// Index paths inserted by the batch update in progress.
    private var insertedIndexPaths: Set<IndexPath> = []

    // MARK: UICollectionViewLayout

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: Self.canvasHeight)
    }

    /// Rebuilds metrics only on the first layout or a width change. Inserts
    /// are handled in prepare(forCollectionViewUpdates:), the only place
    /// that knows whether new items went at the top or the bottom.
    override func prepare() {
        super.prepare()
        guard let collectionView, collectionView.numberOfSections > 0 else {
            metrics = []
            return
        }
        let count = collectionView.numberOfItems(inSection: 0)
        let width = collectionView.bounds.width

        if metrics.isEmpty || width != metricsWidth {
            metricsWidth = width

            // Keep the first item's y so a rotation after a prepend does not
            // move the canvas origin.
            var y = metrics.first?.y ?? 0
            metrics = (0..<count).map { index in
                let height = heightForItem?(index, width) ?? fallbackHeight
                defer { y += height }
                return Metric(y: y, height: height)
            }
        }
    }

    /// Places inserted items without moving existing ones. Inserts before
    /// the old first item stack upward from it (prepend); any others stack
    /// downward and push later items down (append).
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        guard let collectionView else { return }
        let newCount = collectionView.numberOfItems(inSection: 0)
        let width = collectionView.bounds.width

        insertedIndexPaths = Set(updateItems.compactMap { item in
            item.updateAction == .insert ? item.indexPathAfterUpdate : nil
        })
        let inserted = Set(insertedIndexPaths.map(\.item))

        // No inserts, or prepare() already built everything (first page).
        guard !inserted.isEmpty, !metrics.isEmpty,
              metrics.count + inserted.count == newCount else { return }

        // 1. Old metrics into the new index space; new items get a height.
        var result: [Metric] = []
        result.reserveCapacity(newCount)
        var old = metrics.makeIterator()
        for index in 0..<newCount {
            if inserted.contains(index) {
                result.append(Metric(y: 0, height: heightForItem?(index, width) ?? fallbackHeight))
            } else {
                result.append(old.next()!)
            }
        }

        // 2. Prepends: walk upward from the old first item.
        let firstOld = (0..<newCount).first { !inserted.contains($0) }!
        var y = result[firstOld].y
        for index in stride(from: firstOld - 1, through: 0, by: -1) {
            y -= result[index].height
            result[index].y = y
        }

        // 3. The rest: new items sit under their predecessor, old items
        //    shift down by what was inserted above them.
        var shift: CGFloat = 0
        for index in (firstOld + 1)..<max(firstOld + 1, newCount) {
            if inserted.contains(index) {
                result[index].y = result[index - 1].maxY
                shift += result[index].height
            } else {
                result[index].y += shift
            }
        }

        metrics = result
    }

    /// Inserted rows start at `appearFromFrame` instead of fading in.
    override func initialLayoutAttributesForAppearingItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let from = appearFromFrame,
              insertedIndexPaths.contains(indexPath),
              let final = layoutAttributesForItem(at: indexPath) else {
            return super.initialLayoutAttributesForAppearingItem(at: indexPath)
        }
        let start = final.copy() as! UICollectionViewLayoutAttributes
        start.frame = from
        start.zIndex = 1   // fly over the rows sliding up beneath it
        return start
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths.removeAll()
        appearFromFrame = nil
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < metrics.count else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame(forItem: indexPath.item)
        return attributes
    }

    // Linear scan. Rows are sorted by y, so a binary search would do.
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        metrics.indices.compactMap { index in
            let indexPath = IndexPath(item: index, section: 0)
            guard let attributes = layoutAttributesForItem(at: indexPath),
                  attributes.frame.intersects(rect) else { return nil }
            return attributes
        }
    }

    /// Only a width change needs new frames, not a scroll.
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
    }

    // MARK: Helpers

    /// Anchor-relative metric to a frame on the canvas.
    private func frame(forItem index: Int) -> CGRect {
        let metric = metrics[index]
        return CGRect(
            x: 0,
            y: Self.anchorY + metric.y,
            width: collectionViewContentSize.width,
            height: metric.height
        )
    }

    /// Negative insets that hide the empty canvas above the first item and
    /// below the last. The controller adds the safe area on top.
    var hidingInsets: UIEdgeInsets {
        guard let first = metrics.first, let last = metrics.last else {
            return UIEdgeInsets(top: -Self.anchorY, left: 0,
                                bottom: -(Self.canvasHeight - Self.anchorY), right: 0)
        }
        let emptyAbove = Self.anchorY + first.y
        let emptyBelow = Self.canvasHeight - (Self.anchorY + last.maxY)
        return UIEdgeInsets(top: -emptyAbove, left: 0, bottom: -emptyBelow, right: 0)
    }
}
