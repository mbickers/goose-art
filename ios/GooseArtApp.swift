import SwiftUI

@main
struct GooseArtApp: App {
    @State var recentEmojiStore = RecentEmojiService()
    @State var placementService = PlacementService()
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                placementService: placementService,
                recentEmojisStore: recentEmojiStore
            )
        }
    }
}
