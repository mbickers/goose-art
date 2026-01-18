import SwiftUI

struct PlacedEmoji: Identifiable {
    let id = UUID()
    var emoji: String
    var position: CGPoint
}

struct ContentView: View {
    @State private var placedEmojis: [PlacedEmoji] = []
    @State private var recentEmojis: [String] = ["😀", "😎", "🥳", "❤️", "🎨"]
    @State private var emojiFieldValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                ForEach(placedEmojis) { placedEmoji in
                    Text(placedEmoji.emoji)
                        .font(.system(size: 50))
                        .position(placedEmoji.position)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding()
            .dropDestination(for: String.self) { items, location in
                guard let emoji = items.first else { return false }
                let newEmoji = PlacedEmoji(emoji: emoji, position: location)
                placedEmojis.append(newEmoji)
                addToRecents(emoji)

                return true
            }

            Button(role: .destructive) {
                placedEmojis.removeAll()
            } label: {
                Label("Clear Canvas", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 10)

            Spacer()

            VStack(spacing: 0) {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        let background = RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.1))

                        ZStack {
                            TextField(
                                "",
                                text: $emojiFieldValue,
                                prompt: Text("+")
                            )
                            .multilineTextAlignment(.center)
                            .frame(width: 60, height: 60)
                            .onChange(of: emojiFieldValue) {
                                oldValue,
                                newValue in
                                if let lastChar = newValue.last {
                                    emojiFieldValue = String(lastChar)
                                }
                            }
                            .background(
                                background
                            )

                            if !emojiFieldValue.isEmpty {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(width: 60, height: 60)
                                    .draggable(emojiFieldValue) {
                                        Text(emojiFieldValue)
                                            .font(.system(size: 60))
                                    }
                            }
                        }

                        ForEach(recentEmojis, id: \.self) { emoji in
                            Text(emoji)
                                .frame(width: 60, height: 60)
                                .background(
                                    background
                                )
                                .draggable(emoji) {
                                    Text(emoji)
                                        .font(.system(size: 60))
                                }
                        }
                    }
                }
                .font(.system(size: 40))
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
        }
    }

    private func addToRecents(_ emoji: String) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > 10 {
            recentEmojis = Array(recentEmojis.prefix(10))
        }
        if emojiFieldValue == emoji {
            emojiFieldValue = ""
        }
    }
}

#Preview {
    ContentView()
}
