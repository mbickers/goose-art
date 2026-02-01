import SwiftUI

@main
struct GooseArtApp: App {
    @State var recentEmojiStore = RecentEmojiService()
    @State var placementService = FrontendCanvasService()
    
    var body: some Scene {
        WindowGroup {
            CanvasView(
                placementService: placementService,
                recentEmojisStore: recentEmojiStore
            )
        }
    }
}
