//
//  ChatListViewController.swift
//  Steady
//
//  Created by Gaajar on 21/09/26.
//

import OSLog
import UIKit

/// Filter Console by category "paging".
let pagingLog = Logger(subsystem: "Steady", category: "paging")

/// A chat list that loads older history at the top without moving what the
/// user is reading.
///
/// Generic over `Item`: the list only needs an id, a height at a given width,
/// and a cell. Appearance, measurement and paging come from the host through
/// `cellProvider`, `heightProvider` and `onNeedsOlder`. Data goes in through
/// `setItems(_:)`, `prepend(_:)` and `append(_:from:)`.
///
/// The no-jump guarantee comes from `ChatLayout`.
public final class ChatListViewController<Item: Identifiable>: UIViewController
where Item.ID: Sendable {

    // MARK: Configuration

    /// Turns an item into a cell. The host owns all appearance.
    public var cellProvider: ((UICollectionView, IndexPath, Item) -> UICollectionViewCell)?

    /// Height of an item when the row is `width` wide. Asked once per item
    /// per width and cached by id.
    public var heightProvider: ((Item, CGFloat) -> CGFloat)?

    /// The user scrolled into the top `prefetchFraction` of the list. Load
    /// items older than `oldest` and call `prepend(_:)`; `prepend([])` means
    /// there is nothing older. Fires at most once until `prepend(_:)` answers.
    public var onNeedsOlder: ((_ oldest: Item) -> Void)?

    /// Scroll position that triggers `onNeedsOlder`. 0 is the top, 1 the bottom.
    public var prefetchFraction: CGFloat = 0.25

    /// Extra space above the first item.
    public var topInset: CGFloat = 0 {
        didSet { reapplyInsets() }
    }

    /// Extra space below the last item.
    public var bottomInset: CGFloat = 0 {
        didSet { reapplyInsets() }
    }

    /// Shown centred until the first `setItems(_:)`. Nil shows nothing. A
    /// `UIActivityIndicatorView` is started and stopped for you.
    public var loadingView: UIView? = UIActivityIndicatorView(style: .large) {
        didSet {
            teardownLoadingView(oldValue)
            setupLoadingView()
        }
    }

    // MARK: State

    private nonisolated enum Section { case main }

    /// Oldest first. Snapshot item N is always `items[N]`, which lets the
    /// cell provider look items up by index path.
    private var items: [Item] = []

    private var olderPager = Pager()

    // MARK: Views

    private let layout = ChatLayout()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item.ID>!

    private let proxy = ChatListProxy()

    private var hasLoaded = false

    // MARK: Height cache

    /// Valid for `heightCacheWidth` only; text rewraps at a new width.
    private var heightCache: [Item.ID: CGFloat] = [:]
    private var heightCacheWidth: CGFloat = 0

    // MARK: Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupDataSource()
        setupLoadingView()

        layout.heightForItem = { [weak self] index, width in
            self?.height(forItem: index, width: width) ?? 44
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInsets()
    }

    /// The insets can be set before the view loads.
    private func reapplyInsets() {
        guard isViewLoaded else { return }
        updateInsets()
    }

    // MARK: Setup

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        // Meaningless on a 1,000,000 pt canvas.
        collectionView.showsVerticalScrollIndicator = false
        // updateInsets() adds the safe area itself.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive

        proxy.onScroll = { [weak self] in self?.scrolled() }
        proxy.onTap = { [weak self] in self?.view.window?.endEditing(true) }
        collectionView.delegate = proxy

        // Tap to dismiss the keyboard. Ends editing on the window because the
        // composer may live outside this view.
        let tap = UITapGestureRecognizer(target: proxy, action: #selector(ChatListProxy.handleTap))
        tap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tap)

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // Edge to edge; the safe area is handled through insets.
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

    /// Replaces everything and scrolls to the newest item.
    public func setItems(_ newItems: [Item]) {
        hasLoaded = true
        teardownLoadingView(loadingView)

        items = newItems
        applySnapshot(animatingDifferences: false)
        // Run prepare() now so hidingInsets sees every item before scrolling.
        collectionView.layoutIfNeeded()
        updateInsets()
        scrollToBottom(animated: false)
    }

    /// Inserts older items, oldest first, above the current ones. Nothing on
    /// screen moves. An empty array means history is exhausted.
    public func prepend(_ older: [Item]) {
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

    /// Adds one item at the end and scrolls to it. If `sourceFrame` (window
    /// coordinates) is given, the new row animates from there.
    public func append(_ item: Item, from sourceFrame: CGRect? = nil) {
        items.append(item)

        guard let sourceFrame else {
            applySnapshot(animatingDifferences: false)
            collectionView.layoutIfNeeded()
            updateInsets(keepBottomPinned: false)
            scrollToBottom(animated: true)
            return
        }

        // A scroll view's coordinate space is its content space, so the
        // converted rect is usable as a layout frame directly.
        layout.appearFromFrame = collectionView.convert(sourceFrame, from: nil)

        applySnapshot(animatingDifferences: true)
        collectionView.layoutIfNeeded()
        updateInsets(keepBottomPinned: false)
        scrollToBottom(animated: true)
    }

    // MARK: Snapshot

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(\.id), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    // MARK: Measuring

    /// Called from the layout's prepare().
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

    /// Content inset = the layout's hiding insets + safe area + top/bottomInset.
    ///
    /// When the top inset changes near the top, UIScrollView shifts
    /// contentOffset to "keep content in place". Our content did not move,
    /// so that shift would be a visible jump; the offset is restored.
    private func updateInsets(keepBottomPinned: Bool = true) {
        let wasAtBottom = keepBottomPinned && !items.isEmpty && scrollProgress >= 0.99
        let offsetBefore = collectionView.contentOffset

        var insets = layout.hidingInsets
        insets.top += view.safeAreaInsets.top + topInset
        insets.bottom += view.safeAreaInsets.bottom + bottomInset
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = view.safeAreaInsets

        if wasAtBottom {
            // Stay pinned to the newest item.
            scrollToBottom(animated: false)
        } else if collectionView.contentOffset != offsetBefore {
            collectionView.contentOffset = offsetBefore
        }
    }

    // MARK: Scrolling

    private func scrolled() {
        guard scrollProgress < prefetchFraction,
              let oldest = items.first,
              olderPager.beginLoading()
        else { return }
        pagingLog.info("trigger: progress \(self.scrollProgress, format: .fixed(precision: 3)) < \(self.prefetchFraction), asking for older than \(String(describing: oldest.id))")
        onNeedsOlder?(oldest)
    }

    private func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }
        // Content shorter than the screen: the bottom is the top.
        let y = max(bottomOffset, topOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }
}

// MARK: - Scroll position

extension ChatListViewController {

    /// Offset with the first row at the top.
    private var topOffset: CGFloat {
        -collectionView.contentInset.top
    }

    /// Offset with the last row at the bottom.
    private var bottomOffset: CGFloat {
        collectionView.contentSize.height
            + collectionView.contentInset.bottom
            - collectionView.bounds.height
    }

    /// 0 at the top, 1 at the bottom.
    private var scrollProgress: CGFloat {
        let y = collectionView.contentOffset.y
        return (y - topOffset) / max(bottomOffset - topOffset, 1)
    }
}

// MARK: - Objective-C interop

/// A generic class cannot expose `@objc` members, so this non-generic object
/// is the collection view delegate and the tap target, and forwards to the
/// list through closures. The list holds it strongly; the closures capture
/// the list weakly.
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
