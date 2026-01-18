import SwiftUI

struct PlacedEmoji: Identifiable {
    let id = UUID()
    let emoji: Emoji
    let position: CGPoint
    let scale: CGFloat
    let rotation: Angle
}

struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: Angle
}

// TODO: fix offset/size when dropping
// TODO: store size instead of scale (at least, be consistent about units everywhere). Choose units for size in canvas and DragState

struct DragState {
    let emoji: Emoji
    // TODO: say which coordinate system this position is in
    let position: CGPoint
    let scale: CGFloat
    let rotation: Angle

    let secondTouchState: SecondTouchState?

    func with(position: CGPoint) -> DragState {
        return DragState(
            emoji: emoji,
            position: position,
            scale: scale,
            rotation: rotation,
            secondTouchState: secondTouchState
        )
    }

    func with(secondTouchState: SecondTouchState?) -> DragState {
        return DragState(
            emoji: emoji,
            position: position,
            scale: scale,
            rotation: rotation,
            secondTouchState: secondTouchState
        )
    }

    func with(scale: CGFloat, rotation: Angle) -> DragState {
        return DragState(
            emoji: emoji,
            position: position,
            scale: scale,
            rotation: rotation,
            secondTouchState: secondTouchState
        )
    }
}

func lastEmojiInString(_ string: String) -> Emoji? {
    return string.compactMap { Emoji($0) }.last
}

struct ContentView: View {
    @State private var placedEmojis: [PlacedEmoji] = []
    @State private var recentEmojis: [Emoji] = ["😀", "😎", "🥳", "❤️", "🎨"].map {
        Emoji($0)!
    }
    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var dragState: DragState? = nil

    // TODO: this is probably bad way to deal with geometry checking
    @State private var canvasFrame: CGRect = .zero

    private func makeDragGesture(emoji: Emoji) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global).onChanged {
            value in
            guard let dragState else {
                dragState = DragState(
                    emoji: emoji,
                    position: value.location,
                    scale: 1.0,
                    rotation: Angle(degrees: 0),
                    secondTouchState: nil
                )
                return
            }
            self.dragState = dragState.with(position: value.location)
        }.onEnded { value in
            guard let dragState = self.dragState else { return }
            if canvasFrame.contains(dragState.position) {
                let newEmoji = PlacedEmoji(
                    emoji: emoji,
                    position: dragState.position,
                    scale: dragState.scale,
                    rotation: dragState.rotation
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
                        Text(placedEmoji.emoji.stringValue)
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
                                .focused($emojiFieldFocused)
                                .multilineTextAlignment(.center)
                                .frame(width: 60, height: 60)
                                .onChange(of: emojiFieldValue) {
                                    oldValue,
                                    newValue
                                    in
                                    emojiFieldValue =
                                        lastEmojiInString(newValue)?.stringValue
                                        ?? ""
                                }
                                .onChange(of: emojiFieldFocused) {
                                    oldValue,
                                    isFocused in
                                    if !isFocused,
                                        let emoji = lastEmojiInString(
                                            emojiFieldValue
                                        )
                                    {
                                        addToRecents(emoji)
                                    }
                                    emojiFieldValue = ""
                                }
                                .background(background)

                                // Using hacky ZStack because attaching the gesture directly to the TextField interacted badly with TextField interactions. Tried
                                // - using .gesture, including sequencing with LongPressGesture (never triggered)
                                // - highPriorityGesture (both drag and text selection interaction would happen, which was messy experience), same thing with LongPressGesturee
                                // - trying to disable hit testing on TextField, didn't work
                                if let emoji = lastEmojiInString(
                                    emojiFieldValue
                                ),
                                    emojiFieldFocused
                                {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(width: 60, height: 60)
                                        .gesture(
                                            makeDragGesture(emoji: emoji)
                                        )
                                }
                            }

                            ForEach(recentEmojis, id: \.self) { emoji in
                                Text(emoji.stringValue)
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
                Color.blue
                    .opacity(0.3)
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 0,
                        maxHeight: .infinity
                    )
                    .gesture(
                        DragGesture(
                            minimumDistance: 10,
                            coordinateSpace: .global
                        )
                        .onChanged { value in
                            guard
                                let secondTouchState = dragState
                                    .secondTouchState
                            else {
                                self.dragState = dragState.with(
                                    secondTouchState: SecondTouchState(
                                        initialOffset: value.startLocation
                                            - dragState.position,
                                        baseScale: dragState.scale,
                                        baseRotation: dragState.rotation
                                    )
                                )
                                return
                            }

                            let currentOffset =
                                value.location - dragState.position
                            
                            let clampedInitialOffsetNorm = max(
                                secondTouchState.initialOffset
                                    .norm(),
                                1
                            )
                            let clampedScale =
                                (secondTouchState.baseScale
                                * currentOffset.norm()
                                / clampedInitialOffsetNorm).clamped(
                                    // TODO: factor out constants
                                    to: 0.05...10
                                )
                            
                            let initialAngle = secondTouchState.initialOffset.angle()
                            let currentAngle = currentOffset.angle()
                            let rotationDelta = currentAngle - initialAngle
                            let newRotation = secondTouchState.baseRotation + Angle(radians: rotationDelta)
                            
                            self.dragState = dragState.with(
                                scale: clampedScale,
                                rotation: newRotation
                            )
                        }.onEnded {
                            _ in
                            self.dragState = dragState.with(
                                secondTouchState: nil
                            )
                        }

                    )

                Text(dragState.emoji.stringValue)
                    // TODO: factor out shared code for drawing emojis in preview/recent bar/canvas
                    .font(.system(size: 60 * dragState.scale))
                    .rotationEffect(dragState.rotation)
                    .position(dragState.position)
                    .allowsHitTesting(false)
            }
        }
    }

    private func addToRecents(_ emoji: Emoji) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > 10 {
            recentEmojis = Array(recentEmojis.prefix(10))
        }
        if lastEmojiInString(emojiFieldValue) == emoji {
            emojiFieldValue = ""
        }
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
