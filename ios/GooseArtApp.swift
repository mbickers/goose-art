//
//  GooseArtApp.swift
//  goose-art
//
//  Created by Max Bickers on 1/17/26.
//

import SwiftUI

@main
struct GooseArtApp: App {
    @State var recentEmojiStore = RecentEmojiStore(inMemory: false)
    
    var body: some Scene {
        WindowGroup {
            ContentView(recentEmojisStore: recentEmojiStore)
        }
    }
}
