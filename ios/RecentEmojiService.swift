import SwiftUI

@Observable class RecentEmojiService {
    private(set) var recentEmojis: [Emoji]

    init() {
        self.recentEmojis = ["🦆", "❤️", "🪿"].compactMap { Emoji($0) }

        if let data = UserDefaults.standard.data(forKey: "recentEmojis"),
            let decoded = try? JSONDecoder().decode(
                Array<Emoji>.self,
                from: data
            )
        {
            self.recentEmojis = decoded
        }
    }

    func emojiUsed(_ emoji: Emoji) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        recentEmojis = Array(recentEmojis.prefix(100))
        UserDefaults.standard.set(
            try! JSONEncoder().encode(recentEmojis),
            forKey: "recentEmojis"
        )
    }
}
