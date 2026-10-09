//
//  MessageSkeletonView.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import UIKit

/// Placeholder bubbles with a shimmer, shown until the first page arrives.
/// Set as the list's `loadingView`; the list removes it on `setItems(_:)`.
final class MessageSkeletonView: UIView {

    /// Side, width as a fraction of the widest bubble, and line count for each
    /// placeholder, newest first. Repeats until the screen is full.
    private static let pattern: [(isMe: Bool, widthFraction: CGFloat, lines: Int)] = [
        (true, 0.6, 1),
        (false, 0.95, 3),
        (true, 0.8, 2),
        (false, 0.45, 1),
        (false, 0.9, 4),
        (true, 0.65, 1),
        (false, 0.85, 2),
    ]

    private let content = UIView()
    private let shimmer = CAGradientLayer()
    private var bubbles: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(content)

        // The gradient is the content's alpha mask: a bright band sweeps
        // across dimmed bubbles.
        let dim = UIColor.black.withAlphaComponent(0.5).cgColor
        let bright = UIColor.black.cgColor
        shimmer.colors = [dim, bright, dim]
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.locations = [0, 0.5, 1]
        content.layer.mask = shimmer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // The list only centres its loading view, so fill the list from here.
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard let superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalTo: superview.widthAnchor),
            heightAnchor.constraint(equalTo: superview.heightAnchor),
        ])
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startShimmer()
        } else {
            shimmer.removeAllAnimations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
        shimmer.frame = bounds
        layoutBubbles()
    }

    /// Stacks placeholders from the bottom up, sized like real messages, so
    /// the swap to real content does not look like a jump.
    private func layoutBubbles() {
        typealias Metrics = MessageCell.Metrics
        let padding = Metrics.bubblePadding
        let lineHeight = Metrics.font.lineHeight
        let top = safeAreaInsets.top
        var y = bounds.height - safeAreaInsets.bottom

        var index = 0
        while true {
            let item = Self.pattern[index % Self.pattern.count]
            let height = CGFloat(item.lines) * lineHeight + padding.top + padding.bottom
            let width = bounds.width * Metrics.maxBubbleFraction * item.widthFraction
            y -= height + Metrics.rowSpacing
            // Only whole bubbles, none running under the navigation bar.
            guard y >= top else { break }
            let x = item.isMe ? bounds.width - Metrics.sideMargin - width : Metrics.sideMargin

            let bubble = bubble(at: index)
            bubble.frame = CGRect(x: x, y: y, width: width, height: height)
            y -= Metrics.rowSpacing
            index += 1
        }
        // Drop bubbles left over from a taller layout.
        while bubbles.count > index {
            bubbles.removeLast().removeFromSuperview()
        }
    }

    private func bubble(at index: Int) -> UIView {
        if index < bubbles.count { return bubbles[index] }
        let bubble = UIView()
        bubble.backgroundColor = .systemGray5
        bubble.layer.cornerRadius = MessageCell.Metrics.cornerRadius
        bubble.layer.cornerCurve = .continuous
        content.addSubview(bubble)
        bubbles.append(bubble)
        return bubble
    }

    private func startShimmer() {
        // Without motion, the dimmed bubbles alone still read as loading.
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-1.0, -0.5, 0.0]
        sweep.toValue = [1.0, 1.5, 2.0]
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        shimmer.add(sweep, forKey: "shimmer")
    }
}
