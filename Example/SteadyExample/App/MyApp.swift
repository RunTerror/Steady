//
//  MyApp.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import Steady
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Text("Start here")
                    .navigationTitle("Chat")
            }
        }
    }
}

#Preview {
    NavigationStack {
        Text("Start here")
    }
}
