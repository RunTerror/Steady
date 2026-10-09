//
//  ChatContextMenuPreviewing.swift
//  Steady
//
//  Created by Gaajar on 30/09/26.
//

import UIKit

/// Adopt in a cell so a long press lifts only part of it, such as the
/// bubble, instead of the full-width row. The view's corner radius shapes
/// the lifted preview.
public protocol ChatContextMenuPreviewing: UICollectionViewCell {
    var contextMenuPreviewView: UIView { get }
}
