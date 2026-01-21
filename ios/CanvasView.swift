import SwiftUI

// TODO: make public/private consistent

struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: CGFloat  // radians
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
                rotation: placement.rotation,
                isMirrored: placement.isMirrored,
                userId: placement.userId,
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

    func with(scale: CGFloat, rotation: CGFloat) -> ActivePlacementState {
        return ActivePlacementState(
            placement: Placement(
                emoji: placement.emoji,
                position: placement.position,
                scale: scale,
                rotation: rotation,
                isMirrored: placement.isMirrored,
                userId: placement.userId
            ),
            secondTouchState: secondTouchState
        )
    }

    func with(isMirrored: Bool) -> ActivePlacementState {
        return ActivePlacementState(
            placement: Placement(
                emoji: placement.emoji,
                position: placement.position,
                scale: placement.scale,
                rotation: placement.rotation,
                isMirrored: isMirrored,
                userId: placement.userId
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

let buttonBorder = RoundedBorder(cornerRadius: 20, lineWidth: 6)

struct EmojiButton: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 40))
            .frame(width: 60, height: 60)
            .background(color)
            .modifier(buttonBorder)
    }
}

struct ActionButton: View {
    let iconName: String
    let action: () -> Void
    let enabled: Bool

    init(iconName: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.iconName = iconName
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(buttonIconColor)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(yellow)
                .opacity(enabled ? 1.0 : 0.5)
                .modifier(buttonBorder)
        }
        .disabled(!enabled)
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

private let buttonIconColor = darkPurple.opacity(0.5)

struct CanvasView: View {
    let placementService: PlacementService
    let recentEmojisStore: RecentEmojiService

    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var activePlacementState: ActivePlacementState? = nil
    @State private var canvasFrame: CGRect? = nil
    @State private var showingSettings = false

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
            self.activePlacementState =
                activePlacementState?.with(
                    position: placementPosition
                )
                ?? ActivePlacementState(
                    placement: Placement(
                        emoji: emoji,
                        position: placementPosition,
                        scale: 0.3,
                        rotation: 0,
                        isMirrored: false,
                        userId: placementService.userId
                    ),
                    secondTouchState: nil
                )
        }.onEnded { value in
            guard let activePlacementState else { return }

            if activePlacementState.placement.hasValidPosition {
                placementService.place(activePlacementState.placement)
                recentEmojisStore.emojiUsed(
                    activePlacementState.placement.emoji
                )
            }

            self.activePlacementState = nil
        }

        return LongPressGesture(minimumDuration: 0.2).sequenced(
            before: dragGesture
        )
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
            let newRotation = secondTouchState.baseRotation + rotationDelta

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
                    .font(.system(size: 40, weight: .regular))
                    .foregroundColor(buttonIconColor)
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
                    recentEmojisStore.emojiUsed(emoji)
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
                .scaleEffect(x: placement.isMirrored ? -1 : 1, y: 1)
                .rotationEffect(Angle(radians: placement.rotation))
                .position(placement.position * canvasFrame.height + offset)
        } else {
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                ZStack {
                    Rectangle()
                        .fill(blue)

                    ForEach(
                        placementService.placements.enumerated(),
                        id: \.offset
                    ) {
                        (_, placement) in
                        placementView(placement)
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

                HStack(spacing: 10) {
                    ActionButton(
                        iconName: "arrow.uturn.backward",
                        enabled: placementService.canUndo,
                        action: placementService.undo,
                    )

                    ActionButton(
                        iconName:
                            "arrow.left.and.right.righttriangle.left.righttriangle.right",
                        enabled: activePlacementState != nil
                    ) {
                        if let dragState = activePlacementState {
                            activePlacementState = dragState.with(
                                isMirrored: !dragState.placement.isMirrored
                            )
                        }
                    }

                    ActionButton(iconName: "gearshape") {
                        showingSettings = true
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        emojiTextField
                            .modifier(EmojiButton(color: yellow))

                        ForEach(recentEmojisStore.recentEmojis, id: \.self) {
                            emoji in
                            Text(emoji.stringValue)
                                .gesture(
                                    makeDragGesture(emoji: emoji)
                                )
                                .modifier(EmojiButton(color: pink))
                        }
                    }
                }
                .scrollClipDisabled()
            }.padding()

            if let dragState = activePlacementState, let canvasFrame {
                placementView(dragState.placement, offset: canvasFrame.origin)
                    .opacity(dragState.placement.hasValidPosition ? 0.8 : 0.5)
                    // ignores safe area so that status bar and dynamic island to impact placement
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(purple)
        .confirmationDialog("Settings", isPresented: $showingSettings) {
            Button("Clear", role: .destructive, action: placementService.clear)
            Button("Log out", role: .destructive) {}
        }
    }
}

#Preview {
    CanvasView(
        placementService: PlacementService(),
        recentEmojisStore: RecentEmojiService()
    )
}
