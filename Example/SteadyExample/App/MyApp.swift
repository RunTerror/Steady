import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            // Boots straight into the chat list. Swap in PlaygroundMenu()
            // to get the exercises and learning screens back.
            ChatView()
        }
    }
}

/// The chat list plus the composer, inside a SwiftUI navigation stack.
/// ComposerScreen hosts the UIKit list and pins the bar as a safe-area
/// inset, so SwiftUI handles the keyboard and the controller only reads
/// its safe area.
private struct ChatView: View {
    var body: some View {
        NavigationStack {
            ComposerScreen()
        }
    }
}


#Preview {
    ChatView()
}
