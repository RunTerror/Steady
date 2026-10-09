//
//  MyApp.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatScreen()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatScreen()
    }
}
