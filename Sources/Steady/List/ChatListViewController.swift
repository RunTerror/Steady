import ChatList
import OSLog
import UIKit

/// Timing for the paging path. Filter Console / Xcode by category "paging".
let pagingLog = Logger(subsystem: "chat", category: "paging")

/// A chat list that loads older history at the top without moving what the
/// user is reading.
///
/// GENERIC over `Item`. The list knows three things about an item: it has an
/// `id`, it has a height at a given width, and it can be turned into a cell.
/// It knows nothing about messages, text, bubbles, colours or where the data
/// came from. That is what lets one list serve any app.
///
/// Everything app-specific arrives through four closures:
///
///     cellProvider    how an item becomes a cell        (appearance)
///     heightProvider  how tall an item is at a width    (measurement)
///     onNeedsOlder    "the user is near the top"        (paging)
///     onNeedsNewer    reserved for jump-to-message      (not yet)
///
/// And three methods push data in:
///
///     setItems(_:)    the first page. Opens at the newest item.
///     prepend(_:)     older history. Nothing on screen moves.
///     append(_:from:) one new item, optionally flying in from a rect.
///
/// The no-jump guarantee comes from `ChatLayout`: the content size is a
/// fixed canvas that never grows, so a prepend changes one content inset and
/// nothing else. Read that file first; this one is the driver around it.
final class ChatListViewController<Item: Identifiable>: UIViewController
where Item.ID: Sendable {

    // MARK: What the host supplies

    /// Turn an item into a cell. The host owns the entire appearance, which
    /// is why there is no styling API here and never should be: bubble
    /// colour, shape, tails, timestamps and reactions are all decided by
    /// whatever cell comes back from this closure.
    var cellProvider: ((UICollectionView, IndexPath, Item) -> UICollectionViewCell)?

    /// How tall is this item when the row is `width` wide?
    ///
    /// Asked once per item per width; the answer is cached by id. Supply
    /// arithmetic (a known font, an image's aspect ratio) and no measuring
    /// pass runs at all. Measuring an offscreen cell is the slow fallback,
    /// and it is the host's choice to pay for it, not this class's.
    var heightProvider: ((Item, CGFloat) -> CGFloat)?

    /// The user has scrolled into the top `prefetchFraction` of the list.
    /// Load items older than `oldest`, then call `prepend(_:)`. Calling
    /// `prepend([])` means "there is nothing older" and stops further calls.
    ///
    /// Fires at most once until `prepend(_:)` answers, however many scroll
    /// events arrive in between. That guard is `Pager`.
    var onNeedsOlder: ((_ oldest: Item) -> Void)?

    /// Start loading when the scroll position is this far down the content.
    /// 0 is the very top, 1 is the very bottom.
    var prefetchFraction: CGFloat = 0.25

    /// Extra space above the first item. Room for a date header, or just
    /// air so the oldest message is not flush against a navigation bar.
    var topInset: CGFloat = 0 {
        didSet { reapplyInsets() }
    }

    /// Extra space below the last item. Room for a composer that floats
    /// over the list, or a "jump to latest" pill.
    var bottomInset: CGFloat = 0 {
        didSet { reapplyInsets() }
    }

    /// Rows trail the finger and spring back while scrolling, like Messages.
    /// Off gives a plain, rigid scroll. Lives in the layout; see step 7.
    var isScrollSpringEnabled: Bool {
        get { layout.isSpringEnabled }
        set { layout.isSpringEnabled = newValue }
    }

    /// Shown centred while the list is empty and waiting for the first
    /// `setItems(_:)`. Removed as soon as it arrives.
    ///
    /// Any view will do: a branded spinner, a skeleton, an illustration.
    /// Set it to nil for no indicator at all. The default is a plain large
    /// activity indicator, so the common case needs no code.
    ///
    /// A `UIActivityIndicatorView` is started and stopped for you, because
    /// it is the one view that needs it. Anything else is simply added and
    /// removed, and can animate itself.
    var loadingView: UIView? = UIActivityIndicatorView(style: .large) {
        didSet {
            teardownLoadingView(oldValue)
            setupLoadingView()
        }
    }

    // MARK: State

    private nonisolated enum Section { case main }

    /// Oldest first, newest last. The single source of truth.
    ///
    /// The snapshot is always built from this array in the same order, so
    /// item N in the snapshot is `items[N]`. That invariant is what lets the
    /// cell provider look content up by index path in O(1) instead of
    /// keeping a second id-keyed copy of every item.
    private var items: [Item] = []

    private var olderPager = Pager()

    // MARK: Views

    private let layout = ChatLayout()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item.ID>!

    /// Objective-C interop. See ChatListProxy for why this exists.
    private let proxy = ChatListProxy()

    /// False until the first `setItems(_:)`. While false, `loadingView`
    /// is on screen.
    private var hasLoaded = false

    // MARK: Height cache

    /// id -> height, valid for `heightCacheWidth` only. A width change
    /// invalidates every entry at once, because text rewraps.
    private var heightCache: [Item.ID: CGFloat] = [:]
    private var heightCacheWidth: CGFloat = 0

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupDataSource()
        setupLoadingView()

        // The layout asks by INDEX, because that is all it has. Translating
        // index to item, and caching, happens here so the host's provider
        // stays a pure function of (item, width).
        layout.heightForItem = { [weak self] index, width in
            self?.height(forItem: index, width: width) ?? 44
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInsets()
    }

    /// topInset and bottomInset can be set before the view exists, in which
    /// case viewDidLayoutSubviews will pick them up anyway.
    private func reapplyInsets() {
        guard isViewLoaded else { return }
        updateInsets()
    }

    // MARK: Setup

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        // The canvas is 1,000,000 pt tall, so the indicator would be a
        // sliver that never moves. Hide it.
        collectionView.showsVerticalScrollIndicator = false
        // We set contentInset ourselves (hiding insets + safe area). If UIKit
        // also added the safe area, it would be counted twice.
        collectionView.contentInsetAdjustmentBehavior = .never
        // Dragging the list down pulls the keyboard down with the finger.
        collectionView.keyboardDismissMode = .interactive

        proxy.onScroll = { [weak self] in self?.scrolled() }
        proxy.onTap = { [weak self] in self?.view.window?.endEditing(true) }
        collectionView.delegate = proxy

        // Tapping anywhere on the list closes the keyboard. The composer may
        // be a view outside this hierarchy, so end editing on the WINDOW.
        // cancelsTouchesInView stays false so the tap still reaches cells.
        let tap = UITapGestureRecognizer(target: proxy, action: #selector(ChatListProxy.handleTap))
        tap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tap)

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // Pinned to the view's edges, not the safe area. The safe area is
        // handled through insets so content can scroll under the bars.
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item.ID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, _ in
            guard let self,
                  let cellProvider,
                  indexPath.item < items.count
            else { return UICollectionViewCell() }
            return cellProvider(collectionView, indexPath, items[indexPath.item])
        }
    }

    private func setupLoadingView() {
        guard isViewLoaded, !hasLoaded, let loadingView else { return }
        view.addSubview(loadingView)
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        (loadingView as? UIActivityIndicatorView)?.startAnimating()
    }

    private func teardownLoadingView(_ view: UIView?) {
        (view as? UIActivityIndicatorView)?.stopAnimating()
        view?.removeFromSuperview()
    }

    // MARK: Data in

    /// Replace everything and open at the newest item. Used for the first
    /// page, and for a full reload.
    func setItems(_ newItems: [Item]) {
        hasLoaded = true
        teardownLoadingView(loadingView)

        items = newItems
        applySnapshot(animatingDifferences: false)
        // apply() queued the item change; layoutIfNeeded makes the layout
        // prepare() run now, so hidingInsets sees every item before we scroll.
        collectionView.layoutIfNeeded()
        updateInsets()
        scrollToBottom(animated: false)
    }

    /// Older history, oldest first, going in at index 0.
    ///
    /// Nothing on screen moves. The layout places these above the anchor
    /// with negative positions, the top inset shrinks by their total height,
    /// and contentSize and every existing frame are untouched. Note what is
    /// NOT here: no scrollToItem, no offset arithmetic.
    ///
    /// An empty array means history is exhausted and the pager stops asking.
    func prepend(_ older: [Item]) {
        olderPager.finish(receivedCount: older.count)
        guard !older.isEmpty else {
            pagingLog.info("prepend: empty page, history exhausted")
            return
        }

        let clock = ContinuousClock()
        let start = clock.now
        items.insert(contentsOf: older, at: 0)
        applySnapshot(animatingDifferences: false)
        let afterApply = clock.now
        collectionView.layoutIfNeeded()   // runs prepare(): measures the new rows
        let afterLayout = clock.now
        updateInsets()
        let end = clock.now
        pagingLog.info("prepend \(older.count) items: apply \(afterApply - start), layout+measure \(afterLayout - afterApply), insets \(end - afterLayout), total \(end - start)")
    }

    /// One new item at the end, and scroll to it.
    ///
    /// `from` is where the row should animate from, in WINDOW coordinates.
    /// Pass the composer's text field and the cell flies out of it. Pass nil
    /// and the row simply appears.
    func append(_ item: Item, from sourceFrame: CGRect? = nil) {
        items.append(item)

        guard let sourceFrame else {
            applySnapshot(animatingDifferences: false)
            collectionView.layoutIfNeeded()
            updateInsets(keepBottomPinned: false)
            scrollToBottom(animated: true)
            return
        }

        // Window -> collection view. A scroll view's own coordinate space IS
        // its content space (bounds.origin == contentOffset), so this rect
        // is directly usable as a layout frame.
        layout.appearFromFrame = collectionView.convert(sourceFrame, from: nil)

        // An animated apply runs performBatchUpdates. During it the layout
        // answers initialLayoutAttributesForAppearingItem with that frame,
        // and UIKit animates the real cell to its real place. Wrapping the
        // batch in a spring makes that motion, and the rows sliding up,
        // use the spring instead of the default ease.
        UIView.animate(springDuration: 0.45, bounce: 0.25) {
            applySnapshot(animatingDifferences: true)
            collectionView.layoutIfNeeded()
            updateInsets(keepBottomPinned: false)
            scrollToBottom(animated: false)   // inside the block, so it springs too
        }
    }

    // MARK: Snapshot

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(\.id), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    // MARK: Measuring

    /// Answers the layout's question. Runs inside the layout's prepare().
    private func height(forItem index: Int, width: CGFloat) -> CGFloat {
        guard index < items.count, let heightProvider else { return 44 }
        let item = items[index]

        if width != heightCacheWidth {
            heightCache.removeAll()
            heightCacheWidth = width
        }
        if let cached = heightCache[item.id] { return cached }

        let height = heightProvider(item, width)
        heightCache[item.id] = height
        return height
    }

    // MARK: Insets

    /// Three things stack into one content inset, in this order:
    ///
    ///     ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
    ///     :  empty canvas     :   layout.hidingInsets   (large, negative)
    ///     ├───────────────────┤
    ///     │  safe area        │   view.safeAreaInsets   (bars, keyboard)
    ///     ├───────────────────┤
    ///     │  topInset         │   yours
    ///     ├───────────────────┤
    ///     │  first item       │
    ///          ...
    ///     │  last item        │
    ///     ├───────────────────┤
    ///     │  bottomInset      │   yours
    ///     ├───────────────────┤
    ///     │  safe area        │
    ///     :  empty canvas     :
    ///     └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
    ///
    /// The hiding insets are recomputed by the layout after every change, so
    /// this method is the only place the other two get added back.
    ///
    /// UIScrollView has one habit to know about: when the top inset changes
    /// while you are scrolled at (or near) the top, it moves contentOffset
    /// by the same amount to "keep the content in place". On a normal list
    /// that is helpful. On our canvas the content did not move, so that
    /// nudge IS the jump. Put the offset back.
    private func updateInsets(keepBottomPinned: Bool = true) {
        let wasAtBottom = keepBottomPinned && !items.isEmpty && scrollProgress >= 0.99
        let offsetBefore = collectionView.contentOffset

        var insets = layout.hidingInsets
        insets.top += view.safeAreaInsets.top + topInset
        insets.bottom += view.safeAreaInsets.bottom + bottomInset
        // A conversation shorter than the screen starts at the top: the
        // first item sits under the navigation bar and later ones stack
        // down from it until they fill the screen.
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = view.safeAreaInsets

        if wasAtBottom {
            // The bottom edge moved (composer, keyboard, or a new item).
            // A chat pinned to the newest item stays pinned.
            scrollToBottom(animated: false)
        } else if collectionView.contentOffset != offsetBefore {
            collectionView.contentOffset = offsetBefore
        }
    }

    // MARK: Scrolling

    /// Fires on every frame of a scroll, via the proxy.
    private func scrolled() {
        guard scrollProgress < prefetchFraction,
              let oldest = items.first,
              // beginLoading() answers "may I?" and flips to .loading in one
              // step, so two scroll events in a row cannot both get a yes.
              olderPager.beginLoading()
        else { return }
        pagingLog.info("trigger: progress \(self.scrollProgress, format: .fixed(precision: 3)) < \(self.prefetchFraction), asking for older than \(String(describing: oldest.id))")
        onNeedsOlder?(oldest)
    }

    /// A chat opens at the newest item.
    private func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }
        // While the rows are shorter than the screen, bottomOffset is below
        // topOffset. Asking for it would make UIKit bounce back to the top,
        // so clamp: "the bottom" is the top until the content is tall enough.
        let y = max(bottomOffset, topOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }
}

// MARK: - Where are we in the list?
//
// Think of the list as a ruler. 0 is "first item at the top of the screen".
// 1 is "last item at the bottom of the screen".
//
//     0.00 ── first item is at the top of the screen
//      │
//     0.25 ── ask for older items when we get here    ◀ prefetchFraction
//      │
//      │
//     1.00 ── last item is at the bottom of the screen (where the chat opens)
//
// `contentOffset.y` is the canvas y currently at the top of the screen.

extension ChatListViewController {

    /// The smallest contentOffset.y the user can reach: first row at the top.
    ///
    /// UIScrollView's rule: the minimum offset is `-contentInset.top`.
    /// Our top inset is negative (about -500,000, hiding the empty canvas),
    /// so the minimum offset is about +500,000: the anchor.
    private var topOffset: CGFloat {
        -collectionView.contentInset.top
    }

    /// The largest contentOffset.y the user can reach: last row at the bottom.
    ///
    /// UIScrollView's rule: the maximum offset is
    /// `contentSize.height + contentInset.bottom - bounds.height`.
    /// With 30 rows about 1,900 pt tall and an 800 pt screen:
    ///     1,000,000 + (-498,100) - 800  =  501,100
    private var bottomOffset: CGFloat {
        collectionView.contentSize.height
            + collectionView.contentInset.bottom
            - collectionView.bounds.height
    }

    /// 0 at the top, 1 at the bottom.
    ///
    ///     offset  500,000  ->  (500,000 - 500,000) / 1,100  =  0.00   top
    ///     offset  500,275  ->  (500,275 - 500,000) / 1,100  =  0.25   load!
    ///     offset  501,100  ->  (501,100 - 500,000) / 1,100  =  1.00   bottom
    ///
    /// max(..., 1) only matters when the whole chat fits on one screen and
    /// top == bottom; it stops a divide by zero.
    private var scrollProgress: CGFloat {
        let y = collectionView.contentOffset.y
        return (y - topOffset) / max(bottomOffset - topOffset, 1)
    }
}

// MARK: - Objective-C interop

/// The price of making the list generic, paid once.
///
/// A generic class cannot have `@objc` members and cannot usefully conform
/// to an `@objc` protocol, because neither can be represented in the
/// Objective-C runtime, so UIKit would never call them.
/// `UICollectionViewDelegate` is such a protocol, and a gesture recognizer
/// needs a selector. So one small NON-generic object carries both and
/// forwards through closures.
///
/// Both `collectionView.delegate` and a gesture recognizer's target are
/// weak references, so the list holds this object strongly. The closures
/// capture the list weakly, which is what keeps the cycle from closing.
final class ChatListProxy: NSObject, UICollectionViewDelegate {

    var onScroll: (() -> Void)?
    var onTap: (() -> Void)?

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?()
    }

    @objc func handleTap() {
        onTap?()
    }
}
