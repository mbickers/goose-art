import SwiftUI

struct PlacedEmoji: Identifiable {
    let id = UUID()
    var emoji: String
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
}

struct DragState {
    let emoji: String
    // TODO: say which coordinate system this position is in
    let position: CGPoint
}

struct ContentView: View {
    @State private var placedEmojis: [PlacedEmoji] = []
    @State private var recentEmojis: [String] = ["😀", "😎", "🥳", "❤️", "🎨"]
    @State private var emojiFieldValue: String = ""

    @State private var dragState: DragState? = nil

    // TODO: this is probably bad way to deal with geometry checking
    @State private var canvasFrame: CGRect = .zero

    private func makeDragGesture(emoji: String) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global).onChanged {
            value in
            dragState = DragState(emoji: emoji, position: value.location)
        }.onEnded { value in
            NSLog("Drag ended \(value)")
            guard let dragState = self.dragState else { return }
            if canvasFrame.contains(dragState.position) {
                let newEmoji = PlacedEmoji(
                    emoji: emoji,
                    position: dragState.position,
                    scale: 1.0,
                    rotation: Angle(degrees: 0.0)
                )
                placedEmojis.append(newEmoji)
                addToRecents(emoji)
            }

            self.dragState = nil
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("Drag state \(String(describing: dragState))")
                
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(
                            color: .black.opacity(0.1),
                            radius: 10,
                            x: 0,
                            y: 5
                        )

                    ForEach(placedEmojis) { placedEmoji in
                        Text(placedEmoji.emoji)
                            .font(.system(size: 50 * placedEmoji.scale))
                            .rotationEffect(placedEmoji.rotation)
                            .position(placedEmoji.position)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding()
                .overlay(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                canvasFrame = geometry.frame(in: .global)
                            }
                            .onChange(of: geometry.frame(in: .global)) {
                                oldValue,
                                newValue in
                                canvasFrame = newValue
                            }
                    }
                )
                .coordinateSpace(name: "canvas")

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
                                .background(background)

                                if !emojiFieldValue.isEmpty {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(width: 60, height: 60)
                                }
                            }

                            ForEach(recentEmojis, id: \.self) { emoji in
                                Text(emoji)
                                    .frame(width: 60, height: 60)
                                    .background(background)
                                    .gesture(
                                        makeDragGesture(emoji: emoji)
                                    )
                            }
                        }
                    }
                    .font(.system(size: 40))
                    .padding()
                    .background(Color(uiColor: .systemBackground))
                }
            }

            if let dragState = dragState {
                Text(dragState.emoji)
                    .font(.system(size: 60))
                    .position(dragState.position)
                    .allowsHitTesting(false)
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

    private func handleDrop(at location: CGPoint) {
    }
}

// TODO: why do I need this
struct CanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    ContentView()
}
