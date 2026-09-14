import SwiftUI
import Playgrounds

struct ContentView: View {
    
    @State var messages: [Message] = []
    
    var body: some View {
        
    }
}

struct Message: Identifiable {
    let id: String
    let message: String
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
