import SwiftUI

struct Placement {
    let emoji: Emoji
    let position: CGPoint
    let scale: CGFloat
    let rotation: Angle

    var hasValidPosition: Bool {
        return CGRect(x: 0, y: 0, width: 1, height: 1).contains(position)
    }
}

struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: Angle
}

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

struct EmojiButton: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .frame(width: 60, height: 60)
            .background(color)
            .modifier(
                RoundedBorder(
                    cornerRadius: 20,
                    lineWidth: 6
                )
            )
    }
}

struct GeometryTracker: ViewModifier {
    @Binding var binding: CGRect?

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    EmptyView()
                        .onAppear {
                            binding = geometry.frame(in: .global)
                        }
                        .onChange(of: geometry.frame(in: .global)) {
                            oldValue,
                            newValue in
                            binding = newValue
                        }
                }
            )
    }
}

struct Debug: View {
    let description: String
    let value: String

    init<T>(_ description: String, _ value: T) {
        self.description = description
        self.value = String(describing: value)
    }

    var body: some View {
        Text(verbatim: "\(description): \(value)")
            .foregroundColor(.black)
    }
}

struct ContentView: View {
    @State private var placedEmojis: [Placement] = [
        Placement(
            emoji: Emoji("🦆")!,
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 0.5,
            rotation: Angle(radians: 0.5)
        )
    ]
    @State private var recentEmojis: [Emoji] = ["🦆", "❤️", "🪿"].map {
        Emoji($0)!
    }
    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var activePlacementState: ActivePlacementState? = nil
    @State private var canvasFrame: CGRect? = nil

    private func toPlacementCoordinates(globalPoint: CGPoint) -> CGPoint? {
        guard let canvasFrame else { return nil }
        return (globalPoint - canvasFrame.origin).safeDivide(
            canvasFrame.width
        )
    }

    private func makeDragGesture(emoji: Emoji) -> some Gesture {
        let dragGesture = DragGesture(
            minimumDistance: 10,
            coordinateSpace: .global
        ).onChanged {
            value in
            // TODO: figure out better names for the coordinate systems
            guard
                let placementPosition = toPlacementCoordinates(
                    globalPoint: value.location
                )
            else { return }
            guard let activePlacementState else {
                activePlacementState = ActivePlacementState(
                    placement: Placement(
                        emoji: emoji,
                        position: placementPosition,
                        scale: 0.3,
                        rotation: Angle(degrees: 0)
                    ),
                    secondTouchState: nil
                )
                return
            }
            self.activePlacementState = activePlacementState.with(
                position: placementPosition
            )
        }.onEnded { value in
            guard let dragState = self.activePlacementState else { return }

            if dragState.placement.hasValidPosition {
                placedEmojis.append(dragState.placement)
                addToRecents(dragState.placement.emoji)
            }

            self.activePlacementState = nil
        }

        return LongPressGesture().sequenced(before: dragGesture)
    }

    private var secondTouchGesture: some Gesture {
        DragGesture(
            minimumDistance: 10,
            coordinateSpace: .global
        )
        .onChanged { value in
            guard let dragState = activePlacementState,
                let startLocationCanvasSpace = toPlacementCoordinates(
                    globalPoint: value.startLocation
                ),
                let currentLocationCanvasSpace = toPlacementCoordinates(
                    globalPoint: value.location
                )
            else {
                return
            }
            guard
                let secondTouchState = dragState
                    .secondTouchState
            else {
                self.activePlacementState = dragState.with(
                    secondTouchState: SecondTouchState(
                        initialOffset: startLocationCanvasSpace
                            - dragState.placement.position,
                        baseScale: dragState.placement.scale,
                        baseRotation: dragState.placement.rotation
                    )
                )
                return
            }

            let currentOffset =
                currentLocationCanvasSpace - dragState.placement.position

            let clampedInitialOffsetNorm = max(
                secondTouchState.initialOffset
                    .norm(),
                0.01
            )
            let clampedScale =
                (secondTouchState.baseScale
                * 1.5 * currentOffset.norm()
                / clampedInitialOffsetNorm).clamped(
                    // TODO: factor out constants
                    to: 0.05...1
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
        }
    }

    private var emojiTextField: some View {
        ZStack {
            TextField(
                "",
                text: $emojiFieldValue,
                prompt: Text("+")
            )
            .focused($emojiFieldFocused)
            .onAppear { emojiFieldFocused = true }
            .multilineTextAlignment(.center)
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

            // Using hacky ZStack because attaching the gesture directly to the TextField interacted badly with TextField interactions. Tried
            // - using .gesture, including sequencing with LongPressGesture (never triggered)
            // - highPriorityGesture (both drag and text selection interaction would happen, which was messy experience), same thing with LongPressGesturee
            // - trying to disable hit testing on TextField, didn't work
            if let emoji = lastEmojiInString(
                emojiFieldValue
            ),
                emojiFieldFocused
            {
                // Using Rectangle() or EmptyView() does not work here.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        makeDragGesture(emoji: emoji)
                    )
            }
        }
    }

    @ViewBuilder private func placementView(
        _ placement: Placement,
        offset: CGPoint = .zero
    ) -> some View {
        if let canvasFrame = canvasFrame {
            Text(placement.emoji.stringValue)
                .font(.system(size: canvasFrame.height * placement.scale))
                .rotationEffect(placement.rotation)
                .position(placement.position * canvasFrame.height + offset)
        } else {
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // TODO: fix padding when keyboard down
                ZStack {
                    Rectangle()
                        .fill(blue)

                    ForEach(placedEmojis.enumerated(), id: \.offset) {
                        (_, placement) in
                        placementView(placement)
                    }

                    VStack {
                        Debug(
                            "Drag position",
                            activePlacementState?.placement.position
                                .roundedString()
                        )
                        Debug("Canvas frame", canvasFrame)

                        Spacer()
                    }
                }
                .modifier(GeometryTracker(binding: $canvasFrame))
                .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .gesture(
                    secondTouchGesture,
                    isEnabled: activePlacementState != nil
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        emojiTextField
                            .modifier(EmojiButton(color: yellow))

                        ForEach(recentEmojis, id: \.self) { emoji in
                            Text(emoji.stringValue)
                                .gesture(
                                    makeDragGesture(emoji: emoji)
                                )
                                .modifier(EmojiButton(color: pink))
                        }
                    }
                }
                .font(.system(size: 40))
                .padding()
            }

            if let dragState = activePlacementState, let canvasFrame {
                placementView(dragState.placement, offset: canvasFrame.origin)
                    .opacity(dragState.placement.hasValidPosition ? 0.8 : 0.5)
                    // ignores safe area so that status bar and dynamic island to impact placement
                    .ignoresSafeArea()
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

extension CGPoint {
    func roundedString(decimals: Int = 2) -> String {
        return String(format: "(%.\(decimals)f, %.\(decimals)f)", x, y)
    }
}

#Preview {
    ContentView()
}
