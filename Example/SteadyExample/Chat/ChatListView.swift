//
//  ChatListView.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import Steady
import SwiftUI
import UIKit

/// SwiftUI wrapper around Steady's UIKit list.
struct ChatListView: UIViewControllerRepresentable {
    var showsScrollIndicator = false

    /// Lives as long as the view does. Owns the data source.
    final class Coordinator {
        let server = MockServer()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ChatListViewController<Message> {
        let list = ChatListViewController<Message>()

        let registration = UICollectionView.CellRegistration<MessageCell, Message> { cell, _, message in
            cell.configure(with: message)
        }
        list.cellProvider = { collectionView, indexPath, message in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: message)
        }
        list.heightProvider = { message, width in
            MessageCell.height(for: message, width: width)
        }
        list.loadingView = MessageSkeletonView()
        list.contextMenuProvider = { message in
            UIMenu(children: [
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = message.message
                },
            ])
        }

        // Space below the newest message, always.
        list.bottomInset = 12

        let server = context.coordinator.server

        // Fires once the user nears the top, and not again until prepend
        // answers. An empty page tells the list history is exhausted.
        // Weak: the list holds this closure.
        list.onNeedsOlder = { [weak list] oldest in
            Task {
                let older = await server.page(before: oldest.id)
                list?.prepend(older)
                // Space above the oldest message only once there is no more
                // history. Before that, the next page belongs there.
                if older.isEmpty {
                    list?.topInset = 16
                }
            }
        }

        // The list shows its loading view until the first page arrives.
        // setItems touches the collection view, which exists only after the
        // view has loaded.
        Task { [weak list] in
            let latest = await server.latest()
            guard let list else { return }
            list.loadViewIfNeeded()
            list.setItems(latest)
        }
        return list
    }

    func updateUIViewController(_ list: ChatListViewController<Message>, context: Context) {
        list.showsScrollIndicator = showsScrollIndicator
    }
}
