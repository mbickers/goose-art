import SwiftUI

struct Placement {
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

struct ActivePlacementState {
    let placement: Placement
    let secondTouchState: SecondTouchState?

    init(placement: Placement, secondTouchState: SecondTouchState?) {
        self.placement = placement
        self.secondTouchState = secondTouchState
    }

    func with(position: CGPoint) -> ActivePlacementState {
        return ActivePlacementState(
            placement: Placement(
                emoji: placement.emoji,
                position: position,
                scale: placement.scale,
                rotation: placement.rotation
            ),
            secondTouchState: secondTouchState
        )
    }

    func with(secondTouchState: SecondTouchState?) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState
        )
    }

    func with(scale: CGFloat, rotation: Angle) -> ActivePlacementState {
        return ActivePlacementState(
            placement: Placement(
                emoji: placement.emoji,
                position: placement.position,
                scale: scale,
                rotation: rotation
            ),
            secondTouchState: secondTouchState
        )
    }
}

func lastEmojiInString(_ string: String) -> Emoji? {
    return string.compactMap { Emoji($0) }.last
}

let blue = Color(hex: "8DE8E8")
let darkPurple = Color(hex: "2A053E")
let purple = Color(hex: "3D3E5A")
let yellow = Color(hex: "F4C77F")
let pink = Color(hex: "E8A5B3")

struct RoundedBorder: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(darkPurple, lineWidth: lineWidth)
            )
            .padding(lineWidth / 2)
    }
}

struct ContentView: View {
    @State private var placedEmojis: [Placement] = []
    @State private var recentEmojis: [Emoji] = ["🦆", "❤️", "🪿"].map {
        Emoji($0)!
    }
    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var activePlacementState: ActivePlacementState? = nil

    // TODO: this is probably bad way to deal with geometry checking
    @State private var canvasFrame: CGRect = .zero

    private func makeDragGesture(emoji: Emoji) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global).onChanged {
            value in
            guard let activePlacementState else {
                activePlacementState = ActivePlacementState(
                    placement: Placement(
                        emoji: emoji,
                        position: value.location,
                        scale: 1.0,
                        rotation: Angle(degrees: 0)
                    ),
                    secondTouchState: nil
                )
                return
            }
            self.activePlacementState = activePlacementState.with(
                position: value.location
            )
        }.onEnded { value in
            guard let dragState = self.activePlacementState else { return }
            if canvasFrame.contains(dragState.placement.position) {
                placedEmojis.append(dragState.placement)
                addToRecents(dragState.placement.emoji)
            }

            self.activePlacementState = nil
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(blue)

                    ForEach(placedEmojis.enumerated(), id: \.offset) {
                        (_, placedEmoji) in
                        Text(placedEmoji.emoji.stringValue)
                            .font(.system(size: 50 * placedEmoji.scale))
                            .rotationEffect(placedEmoji.rotation)
                            .position(placedEmoji.position)
                    }

                    VStack {
                        Text(
                            "Drag state \(String(describing: activePlacementState))"
                        )
                        .foregroundColor(.black)
                        Text("Canvas frame \(String(describing: canvasFrame))")
                            .foregroundColor(.black)

                        Spacer()
                    }
                }
                .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
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
                .gesture(
                    DragGesture(
                        minimumDistance: 10,
                        coordinateSpace: .global
                    )
                    .onChanged { value in
                        guard let dragState = activePlacementState else {
                            return
                        }
                        guard
                            let secondTouchState = dragState
                                .secondTouchState
                        else {
                            self.activePlacementState = dragState.with(
                                secondTouchState: SecondTouchState(
                                    initialOffset: value.startLocation
                                        - dragState.placement.position,
                                    baseScale: dragState.placement.scale,
                                    baseRotation: dragState.placement.rotation
                                )
                            )
                            return
                        }

                        let currentOffset =
                            value.location - dragState.placement.position

                        let clampedInitialOffsetNorm = max(
                            secondTouchState.initialOffset
                                .norm(),
                            1
                        )
                        let clampedScale =
                            (secondTouchState.baseScale
                            * 1.5 * currentOffset.norm()
                            / clampedInitialOffsetNorm).clamped(
                                // TODO: factor out constants
                                to: 0.05...10
                            )

                        let initialAngle = secondTouchState.initialOffset
                            .angle()
                        let currentAngle = currentOffset.angle()
                        let rotationDelta = currentAngle - initialAngle
                        let newRotation =
                            secondTouchState.baseRotation
                            + Angle(radians: rotationDelta)

                        self.activePlacementState = dragState.with(
                            scale: clampedScale,
                            rotation: newRotation
                        )
                    }.onEnded {
                        _ in
                        guard let dragState = activePlacementState else {
                            return
                        }
                        self.activePlacementState = dragState.with(
                            secondTouchState: nil
                        )
                    },
                    isEnabled: activePlacementState != nil
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ZStack {
                            TextField(
                                "",
                                text: $emojiFieldValue,
                                prompt: Text("+")
                            )
                            .focused($emojiFieldFocused)
                            .onAppear { emojiFieldFocused = true }
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
                            .background(yellow)

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
                        .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))

                        ForEach(recentEmojis, id: \.self) { emoji in
                            Text(emoji.stringValue)
                                .gesture(
                                    makeDragGesture(emoji: emoji)
                                )
                                .frame(width: 60, height: 60)
                                .background(pink)
                                .modifier(
                                    RoundedBorder(
                                        cornerRadius: 20,
                                        lineWidth: 6
                                    )
                                )
                        }
                    }
                }
                .font(.system(size: 40))
                .padding()
            }

            if let dragState = activePlacementState {
                Text(dragState.placement.emoji.stringValue)
                    // TODO: factor out shared code for drawing emojis in preview/recent bar/canvas
                    .font(.system(size: 60 * dragState.placement.scale))
                    .background(Color.yellow.opacity(0.3))
                    .rotationEffect(dragState.placement.rotation)
                    .position(dragState.placement.position)
                    .allowsHitTesting(false)
            }
        }.background(purple)
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
