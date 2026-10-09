//
//  MessageCell.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import Steady
import UIKit

/// A chat bubble: right-aligned and tinted for my messages, left-aligned and
/// grey for theirs.
final class MessageCell: UICollectionViewCell, ChatContextMenuPreviewing {

    /// Every size the cell uses. The height provider must measure with these
    /// same values, or rows will clip or leave gaps.
    enum Metrics {
        static let font = UIFont.preferredFont(forTextStyle: .body)
        /// Gap between the bubble and the screen edge.
        static let sideMargin: CGFloat = 12
        /// Gap above and below the bubble, so rows do not touch.
        static let rowSpacing: CGFloat = 4
        /// Text inset inside the bubble.
        static let bubblePadding = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        /// A bubble is at most this fraction of the row width.
        static let maxBubbleFraction: CGFloat = 0.75
        static let cornerRadius: CGFloat = 18
    }

    /// Row height for `message` in a row `width` wide. Mirrors the
    /// constraints below: the text wraps at the widest the bubble may be,
    /// minus its padding.
    static func height(for message: Message, width: CGFloat) -> CGFloat {
        let padding = Metrics.bubblePadding
        let textWidth = width * Metrics.maxBubbleFraction - padding.left - padding.right
        let text = NSAttributedString(string: message.message, attributes: [.font: Metrics.font])
        let textHeight = text.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        return ceil(textHeight + padding.top + padding.bottom + 2 * Metrics.rowSpacing)
    }

    private let bubble = UIView()
    private let label = UILabel()

    /// A long press lifts the bubble, not the full-width row.
    var contextMenuPreviewView: UIView { bubble }

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        bubble.layer.cornerRadius = Metrics.cornerRadius
        bubble.layer.cornerCurve = .continuous
        bubble.clipsToBounds = true

        label.font = Metrics.font
        label.numberOfLines = 0

        contentView.addSubview(bubble)
        bubble.addSubview(label)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let padding = Metrics.bubblePadding
        leadingConstraint = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.sideMargin)
        trailingConstraint = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.sideMargin)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.rowSpacing),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.rowSpacing),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: Metrics.maxBubbleFraction),

            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: padding.top),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -padding.bottom),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: padding.left),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -padding.right),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: Message) {
        label.text = message.message

        // Pin one side only; the bubble hugs its text on the other.
        // Deactivate before activating, so both are never on at once.
        let (on, off) = message.isMe
            ? (trailingConstraint!, leadingConstraint!)
            : (leadingConstraint!, trailingConstraint!)
        off.isActive = false
        on.isActive = true

        bubble.backgroundColor = message.isMe ? .tintColor : .secondarySystemBackground
        label.textColor = message.isMe ? .white : .label
    }
}
