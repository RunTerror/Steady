// swift-tools-version: 6.2
//
//  ChatList
//  A chat message list that loads older history without moving what the
//  user is reading.
//
//  Created by Gaajar on 21/09/26.
//
//  SwiftPM has no author field in the manifest, so attribution lives here
//  and in README.md. If this is ever published, the git remote and the tag
//  become the identity consumers actually resolve against.

import PackageDescription

let package = Package(
    name: "ChatList",
    // Liquid Glass in the composer needs iOS 26. The app targets 27, which
    // is allowed: a package may support MORE than its consumer needs.
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "ChatList", targets: ["ChatList"]),
    ],
    targets: [
        .target(
            name: "ChatList",
            swiftSettings: [
                // Match the app target exactly, or code moving across the
                // boundary would change meaning:
                //   SWIFT_VERSION = 5.0
                .swiftLanguageMode(.v5),
                //   SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
                // Every type here is on the main actor unless it says
                // `nonisolated`, same as in the app.
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
