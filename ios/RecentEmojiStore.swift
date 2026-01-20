import SwiftUI
import Combine

@Observable class RecentEmojiStore {
    private(set) var recentEmojis: [Emoji]
    
    init(inMemory: Bool) {
        self.recentEmojis = ["🦆", "❤️", "🪿"].compactMap { Emoji($0) }
    }
    
    func emojiUsed(_ emoji: Emoji) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        recentEmojis = Array(recentEmojis.prefix(10))
    }
}
