import UIKit

/// The chat list's own layout.
///
/// STEP 2: a fixed canvas, fixed row heights, stacked downward.
/// STEP 3: real row heights. The layout asks `heightForItem` for each one.
/// STEP 4: prepend. Items inserted before the first one grow UPWARD from it.
/// STEP 6: send animation. A row can be told where to appear FROM.
/// STEP 7: springy scroll. Rows lag behind the finger and spring back.
///
/// The one idea, from Learning 3: the content size NEVER changes. It is a
/// 1,000,000 pt canvas and the first message sits in the middle of it.
/// Later, older messages will go above the middle and newer ones below.
/// The empty canvas on either side is hidden with negative content insets.
/// Because contentSize never grows and contentOffset is never touched, a
/// prepend cannot move what the user is reading.
///
/// Positions are stored RELATIVE to the anchor, so an item above the anchor
/// has a negative `y`. Only when a frame is handed to UIKit do we add
/// `anchorY`, because content coordinates must be positive.
///
/// The canvas, top to bottom. Canvas coordinates on the left, anchor-
/// relative `Metric.y` on the right. The dotted parts are real content
/// area as far as UIScrollView knows, but the negative insets pull the
/// scrollable range in so the user can never reach them.
///
///     canvas y                                       metric y
///     0          ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
///                :                               :
///                :   empty canvas                :
///                :   hidden by                   :   (step 3: older
///                :   contentInset.top < 0        :    rows grow up
///                :                               :    into here,
///                :                               :    y < 0)
///     anchorY    ├───────────────────────────────┤  0        ◀ first row's top
///     500,000    │ row 0                         │
///                ├───────────────────────────────┤  44
///                │ row 1  (two lines)            │
///                │                               │
///                ├───────────────────────────────┤  108
///                │ ...                           │
///                ├───────────────────────────────┤
///                │ row 29                        │
///                ├───────────────────────────────┤  ≈1900    ◀ last.maxY
///                :                               :
///                :   empty canvas                :   (step 5: newer
///                :   hidden by                   :    rows grow down
///                :   contentInset.bottom < 0     :    into here)
///                :                               :
///     1,000,000  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
///
///     scrollable range = [ -inset.top , canvasHeight + inset.bottom - bounds.height ]
///                      = [ anchorY + first.y ,  anchorY + last.maxY - bounds.height ]
///                      = exactly the rows, nothing else
///
/// Not here yet: deletes, edits that change a row's height.
final class ChatLayout: UICollectionViewLayout {

    static let canvasHeight: CGFloat = 1_000_000
    static let anchorY: CGFloat = canvasHeight / 2

    /// Where one item is, relative to the anchor.
    struct Metric {
        var y: CGFloat
        var height: CGFloat
        var maxY: CGFloat { y + height }
    }

    /// One entry per item in section 0, in item order.
    private(set) var metrics: [Metric] = []

    /// "How tall is item `index` when the row is `width` wide?"
    ///
    /// The layout knows nothing about messages, only counts and frames, so
    /// it asks the controller. The controller measures with a sizing cell.
    /// Heights depend on width (text wraps), which is why width is passed.
    var heightForItem: ((_ index: Int, _ width: CGFloat) -> CGFloat)?

    /// Used when nobody has set heightForItem, e.g. in a preview.
    var fallbackHeight: CGFloat = 80

    /// Width the metrics were computed for. A different width means every
    /// height may have changed, so prepare() rebuilds.
    private var metricsWidth: CGFloat = 0

    /// Where a row inserted in the NEXT animated batch update should start
    /// its animation, in content coordinates. UIKit animates it from here
    /// to its real frame. Set by the controller before an animated apply,
    /// cleared when the batch finishes.
    var appearFromFrame: CGRect?

    /// Index paths inserted by the batch update in progress.
    private var insertedIndexPaths: Set<IndexPath> = []

    // MARK: Springy scroll (step 7)
    //
    // The iMessage feel: while scrolling, rows far from the finger trail a
    // little behind it and then spring back into place, so the list
    // stretches and settles like a slinky.
    //
    // How it works. Every VISIBLE row gets a UIAttachmentBehavior, a spring
    // tied to the spot where the row belongs. On each scroll frame
    // (shouldInvalidateLayout(forBoundsChange:)) the row's centre is
    // nudged by the scroll delta scaled DOWN by its distance from the
    // touch, so it moves less than the content did and falls behind. The
    // spring then pulls it back to its anchor, and the animator calls
    // invalidateLayout() on every tick so UIKit redraws the cells at the
    // in-between positions. The animator owns the attributes objects; we
    // hand those same objects back from layoutAttributesForItem(at:).

    /// Turn the effect off for a plain, rigid scroll.
    var isSpringEnabled = true

    /// How much of the scroll a row at the far end of `springReach` fails
    /// to keep up with. 0 is no effect at all, 1 is a full slinky where
    /// far rows stand still while the content moves under them.
    var springStrength: CGFloat = 0.5

    /// Distance (in points) from the touch at which a row trails by the
    /// full `springStrength`. Rows nearer the finger trail proportionally
    /// less; the row under it does not trail at all.
    var springReach: CGFloat = 1500

    /// Spring settle. Damping below 1 lets rows overshoot a touch before
    /// resting, which is the wobble. Frequency is how quickly they settle.
    var springDamping: CGFloat = 0.8
    var springFrequency: CGFloat = 1.2

    private lazy var animator = UIDynamicAnimator(collectionViewLayout: self)

    /// The attributes the animator is driving, by index path. These are the
    /// live objects: the animator mutates their centre in place.
    private var springAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    /// The last scroll delta, so a row that scrolls into view mid-drag
    /// starts with the same lag as its neighbours instead of snapping.
    private var latestScrollDelta: CGFloat = 0

    /// How far each row was from its rest position when the springs were
    /// last torn down, keyed by rest centre y. A prepend does not move
    /// existing rows, so the same key finds the same row afterwards and
    /// the rebuilt spring starts where the old one left off. Without this
    /// a page arriving mid-scroll snaps every trailing row to rest: the
    /// jump. Consumed by the next tileSprings().
    private var carriedDisplacements: [CGFloat: CGFloat] = [:]

    // MARK: The questions UIKit asks a layout

    /// How big is the content? Always the same answer. This is the trick.
    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: Self.canvasHeight)
    }

    /// Work out where everything goes. Runs before the first layout and
    /// after every invalidation.
    ///
    /// Only two cases rebuild everything here: the very first layout, and a
    /// width change. A COUNT change is deliberately ignored here, because
    /// this method cannot tell whether the new items went at the top or
    /// the bottom. prepare(forCollectionViewUpdates:) below can, and it is
    /// always called right after this one during a batch update.
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

            // Stack downward from wherever the first item already is (0 on
            // the very first layout). Keeping the first item's y on a width
            // change means a rotation after a prepend does not move the
            // canvas origin.
            var y = metrics.first?.y ?? 0
            metrics = (0..<count).map { index in
                let height = heightForItem?(index, width) ?? fallbackHeight
                defer { y += height }
                return Metric(y: y, height: height)
            }
            // Every frame may have moved, so every spring is now wrong.
            resetSprings()
        }

        // Runs on every prepare(), which is every scroll frame and every
        // animator tick: attach rows that scrolled in, drop rows that left.
        tileSprings()
    }

    /// UIKit calls this during performBatchUpdates with every insert and
    /// delete, and where each one landed. This is the only place that knows
    /// "20 items were inserted at 0...19", so it is the only place that can
    /// keep the existing items exactly where they were.
    ///
    ///   - Inserts BEFORE the old first item: stack upward from it. Their y
    ///     values are negative. Nothing else changes. (Prepend.)
    ///   - Inserts anywhere else: stack downward, pushing later items down.
    ///     (Append, or a rare middle insert.)
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        guard let collectionView else { return }
        let newCount = collectionView.numberOfItems(inSection: 0)
        let width = collectionView.bounds.width

        insertedIndexPaths = Set(updateItems.compactMap { item in
            item.updateAction == .insert ? item.indexPathAfterUpdate : nil
        })
        let inserted = Set(insertedIndexPaths.map(\.item))

        // Nothing to do if there were no inserts, or if prepare() already
        // built these metrics from scratch (the first page).
        guard !inserted.isEmpty, !metrics.isEmpty,
              metrics.count + inserted.count == newCount else { return }

        // 1. Lay the old metrics into the new index space. New items get a
        //    height now and a y in the next two passes.
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

        // 2. Prepends: walk backward from the old first item, subtracting.
        let firstOld = (0..<newCount).first { !inserted.contains($0) }!
        var y = result[firstOld].y
        for index in stride(from: firstOld - 1, through: 0, by: -1) {
            y -= result[index].height
            result[index].y = y
        }

        // 3. Everything after: new items sit under their predecessor, and
        //    old items below them shift down by what was inserted so far.
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

        // Index paths and frames both changed. Rebuild the springs so the
        // animator drives the new positions, not the stale ones.
        resetSprings()
        tileSprings()
    }

    /// UIKit asks this for every item inserted in an animated batch update:
    /// "where does this cell start?" It then animates the cell from that
    /// frame to layoutAttributesForItem(at:). The default is the final
    /// frame at alpha 0, a fade. Ours starts at the composer's capsule.
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

    /// End of the batch. Forget the one-shot animation state.
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths.removeAll()
        appearFromFrame = nil
    }

    /// Where is this one item?
    ///
    /// If the animator is driving this row, hand back ITS object: that is
    /// where the spring has put the row right now, not where it belongs.
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        if let live = springAttributes[indexPath] { return live }
        return restAttributes(at: indexPath)
    }

    /// Where the row belongs, ignoring any spring in progress.
    private func restAttributes(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < metrics.count else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame(forItem: indexPath.item)
        return attributes
    }

    /// Which items are inside this rect? Called on every scroll.
    /// Linear scan for now; a binary search comes with self-sizing.
    ///
    /// Tests the LIVE frame, so a row that is still springing into view is
    /// drawn where it is, not skipped because its rest frame is off screen.
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        metrics.indices.compactMap { index in
            let indexPath = IndexPath(item: index, section: 0)
            guard let attributes = layoutAttributesForItem(at: indexPath),
                  attributes.frame.intersects(rect) else { return nil }
            return attributes
        }
    }

    /// Scrolling changes bounds sixty times a second.
    ///
    /// Without springs, only a width change needs new frames. With springs,
    /// every frame nudges the rows, and we invalidate so prepare() can
    /// attach rows that just scrolled into view.
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        let widthChanged = newBounds.width != collectionView.bounds.width
        guard isSpringEnabled else { return widthChanged }

        // Only the user's finger, or the momentum it left behind, gets the
        // spring. A programmatic jump (opening at the newest item, the
        // inset nudge after a prepend, scrolling to a sent message) moves
        // the bounds too, but the rows should simply be where they belong.
        guard collectionView.isDragging || collectionView.isDecelerating else {
            latestScrollDelta = 0
            return true
        }

        let delta = newBounds.origin.y - collectionView.bounds.origin.y
        latestScrollDelta = delta
        let touch = collectionView.panGestureRecognizer.location(in: collectionView)

        for case let behavior as UIAttachmentBehavior in animator.behaviors {
            guard let item = behavior.items.first as? UICollectionViewLayoutAttributes else { continue }
            var center = item.center
            center.y += lag(for: delta, anchorY: behavior.anchorPoint.y, touchY: touch.y)
            item.center = center
            // Tell the animator we moved its item under it, so the spring
            // starts pulling from the new spot instead of overwriting it.
            animator.updateItem(usingCurrentState: item)
        }
        return true
    }

    // MARK: Spring helpers

    /// How far a row at `anchorY` should be pushed, in CONTENT coordinates,
    /// for a scroll of `delta`.
    ///
    /// Coordinates matter here. Scrolling moves the bounds, so a row whose
    /// content position is unchanged moves rigidly with everything else.
    /// Adding the whole `delta` to its content position cancels that out:
    /// it stays put on screen, trailing the scroll completely, and the
    /// spring has to pull it back.
    ///
    /// So: a row under the finger gets 0 and scrolls exactly. A row
    /// `springReach` points away, or further, gets `delta * springStrength`
    /// and trails by that much. Everything in between scales linearly.
    private func lag(for delta: CGFloat, anchorY: CGFloat, touchY: CGFloat) -> CGFloat {
        let resistance = min(abs(touchY - anchorY) / springReach, 1)
        return delta * resistance * springStrength
    }

    /// Attach a spring to every row in (and just around) the visible rect,
    /// and detach the ones that scrolled away. Cheap: a linear scan over
    /// metrics, which layoutAttributesForElements does anyway.
    private func tileSprings() {
        guard isSpringEnabled, let collectionView else { return }

        // A margin above and below so a row is already attached, and
        // already lagging, by the time it scrolls on screen.
        let region = collectionView.bounds.insetBy(dx: 0, dy: -collectionView.bounds.height / 2)
        let wanted = Set(metrics.indices.lazy
            .filter { self.frame(forItem: $0).intersects(region) }
            .map { IndexPath(item: $0, section: 0) })

        for case let behavior as UIAttachmentBehavior in animator.behaviors {
            guard let item = behavior.items.first as? UICollectionViewLayoutAttributes else { continue }
            if !wanted.contains(item.indexPath) {
                animator.removeBehavior(behavior)
                springAttributes[item.indexPath] = nil
            }
        }

        let touch = collectionView.panGestureRecognizer.location(in: collectionView)
        for indexPath in wanted where springAttributes[indexPath] == nil {
            guard let attributes = restAttributes(at: indexPath) else { continue }
            let behavior = UIAttachmentBehavior(item: attributes, attachedToAnchor: attributes.center)
            behavior.length = 0
            behavior.damping = springDamping
            behavior.frequency = springFrequency

            var center = attributes.center
            if let carried = carriedDisplacements[center.y] {
                // This row had a spring before the last rebuild. Resume it
                // exactly where it was so nothing visibly moves.
                center.y += carried
            } else if latestScrollDelta != 0 {
                // Mid-scroll, start the newcomer with the same lag as its
                // neighbours so it does not pop in at rest while they trail.
                center.y += lag(for: latestScrollDelta, anchorY: behavior.anchorPoint.y, touchY: touch.y)
            }
            attributes.center = center

            animator.addBehavior(behavior)
            springAttributes[indexPath] = attributes
        }
        carriedDisplacements.removeAll()
    }

    /// Forget every spring, remembering how far each row was from rest so
    /// the next tileSprings() can resume it rather than snap it.
    private func resetSprings() {
        carriedDisplacements.removeAll()
        for case let behavior as UIAttachmentBehavior in animator.behaviors {
            guard let item = behavior.items.first as? UICollectionViewLayoutAttributes else { continue }
            let displacement = item.center.y - behavior.anchorPoint.y
            if displacement != 0 {
                carriedDisplacements[behavior.anchorPoint.y] = displacement
            }
        }
        animator.removeAllBehaviors()
        springAttributes.removeAll()
    }

    // MARK: Helpers

    /// Anchor-relative metric -> absolute frame on the canvas.
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
    /// below the last one. The controller adds the safe area on top; the
    /// layout does not know about it.
    var hidingInsets: UIEdgeInsets {
        guard let first = metrics.first, let last = metrics.last else {
            // No items yet: hide the whole canvas.
            return UIEdgeInsets(top: -Self.anchorY, left: 0,
                                bottom: -(Self.canvasHeight - Self.anchorY), right: 0)
        }
        let emptyAbove = Self.anchorY + first.y
        let emptyBelow = Self.canvasHeight - (Self.anchorY + last.maxY)
        return UIEdgeInsets(top: -emptyAbove, left: 0, bottom: -emptyBelow, right: 0)
    }
}
