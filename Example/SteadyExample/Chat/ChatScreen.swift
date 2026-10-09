//
//  ChatScreen.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import SwiftUI

/// The chat list plus the demo's options.
struct ChatScreen: View {
    @State private var showsScrollIndicator = false

    var body: some View {
        ChatListView(showsScrollIndicator: showsScrollIndicator)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Options", systemImage: "ellipsis") {
                        Toggle("Show Scroll Bar", isOn: $showsScrollIndicator)
                    }
                }
            }
    }
}

#Preview {
    NavigationStack {
        ChatScreen()
    }
}
