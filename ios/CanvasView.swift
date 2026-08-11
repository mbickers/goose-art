import SwiftUI

// TODO: make public/private consistent

struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: CGFloat  // radians
}

struct ActivePlacementState {
    enum Source {
        case palette
        case canvas
    }

    let placement: Placement
    let secondTouchState: SecondTouchState?
    let source: Source

    init(
        placement: Placement,
        secondTouchState: SecondTouchState?,
        source: Source
    ) {
        self.placement = placement
        self.secondTouchState = secondTouchState
        self.source = source
    }

    func with(placement: Placement) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState,
            source: source
        )
    }

    func with(secondTouchState: SecondTouchState?) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState,
            source: source
        )
    }
}

func lastEmojiInString(_ string: String) -> Emoji? {
    return string.compactMap { Emoji($0) }.last
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

struct CanvasView: View {
    let placementService: DistributedStateMachineClient<[Placement], CanvasAction>
    let logout: (() -> Void)?

    @State private var recentEmojisStore = RecentEmojiService()

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

    private func makeDragGesture(
        source: ActivePlacementState.Source,
        makePlacement: @escaping (CGPoint) -> Placement
    ) -> some Gesture {
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
            let activePlacementState =
                activePlacementState
                ?? ActivePlacementState(
                    placement: makePlacement(placementPosition),
                    secondTouchState: nil,
                    source: source
                )
            self.activePlacementState = activePlacementState.with(
                placement:
                    activePlacementState.placement.with(
                        position: placementPosition
                    )
            )
        }.onEnded { _ in
            dropActivePlacement()
        }

        return LongPressGesture(minimumDuration: 0.2).sequenced(
            before: dragGesture
        )
    }

    private func makePaletteDragGesture(emoji: Emoji) -> some Gesture {
        return makeDragGesture(
            source: .palette,
            makePlacement: { placementPosition in
                Placement(
                    emoji: emoji,
                    position: placementPosition,
                    scale: 0.3,
                    rotation: 0,
                    isMirrored: false,
                    id: UUID().uuidString,
                )
            }
        )
    }

    // reuses the placement's id so that dropping it upserts rather than duplicates
    private func makePickupGesture(placement: Placement) -> some Gesture {
        return makeDragGesture(source: .canvas, makePlacement: { _ in placement })
    }

    private func dropActivePlacement() {
        guard let state = activePlacementState else { return }
        activePlacementState = nil

        switch (state.source, state.placement.hasValidPosition) {
        case (.palette, true):
            placementService.apply(.upsert(placement: state.placement))
            recentEmojisStore.emojiUsed(state.placement.emoji)
        case (.canvas, true):
            placementService.apply(.upsert(placement: state.placement))
        case (.canvas, false):
            placementService.apply(.remove(placementId: state.placement.id))
        case (.palette, false):
            break
        }
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
                placement: dragState.placement.with(
                    scale: clampedScale,
                    rotation: newRotation
                )
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
            if emojiFieldValue == "" {
                Image(systemName: "plus")
                    .font(.rounded(size: 30, weight: .semibold))
                    .foregroundColor(Palette.darkPurple.opacity(0.5))
            }

            TextField("", text: $emojiFieldValue)
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
                        makePaletteDragGesture(emoji: emoji)
                    )
            }
        }
    }

    // positioning is left to the caller so that gestures can be attached before
    // .position, which otherwise expands to fill the whole canvas
    @ViewBuilder private func placementGlyph(_ placement: Placement)
        -> some View
    {
        if let canvasFrame = canvasFrame {
            Text(placement.emoji.stringValue)
                .font(.rounded(size: canvasFrame.height * placement.scale))
                // the canvas proposes less width than the full-screen drag preview,
                // so without this a large glyph gets a narrower frame in one than
                // the other and .position centers them differently
                .fixedSize()
                .scaleEffect(x: placement.isMirrored ? -1 : 1, y: 1)
                .rotationEffect(Angle(radians: placement.rotation))
        } else {
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                ZStack {
                    Rectangle()
                        .fill(Palette.blue)

                    if let canvasFrame {
                        ForEach(
                            placementService.state,
                            id: \.id
                        ) {
                            placement in
                            let placementIsBeingDragged =
                                activePlacementState?.placement.id == placement.id
                            placementGlyph(placement)
                                .contentShape(Rectangle())
                                .gesture(
                                    makePickupGesture(placement: placement)
                                )
                                .opacity(placementIsBeingDragged ? 0.1 : 1)
                                .transition(
                                    AnyTransition.scale(scale: 1.25).combined(with: .opacity)
                                )
                                .position(
                                    placement.position * canvasFrame.height
                                )
                        }
                    }

                    // Sibling of the glyphs rather than a modifier on this ZStack:
                    // a gesture on an ancestor of the glyph holding the active drag
                    // competes with it for the same touch instead of taking the
                    // second finger, and the drag then never ends. Layering it on
                    // top also stops a second finger from picking up another emoji.
                    if activePlacementState != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(secondTouchGesture)
                    }
                }
                // keyed on ids so only placements coming and going animate: a dragged
                // placement's position has to stay glued to the finger
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.55),
                    value: placementService.state.map(\.id)
                )
                .modifier(GeometryTracker(binding: $canvasFrame))
                .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                HStack(spacing: 10) {
                    CustomButton(
                        content: .icon(
                            systemName:
                                "arrow.left.and.right.righttriangle.left.righttriangle.right"
                        ),
                        enabled: activePlacementState != nil
                    ) {
                        if let dragState = activePlacementState {
                            activePlacementState = dragState.with(
                                placement: dragState.placement.with(
                                    isMirrored: !dragState.placement.isMirrored
                                )
                            )
                        }
                    }

                    CustomButton(
                        content: .icon(systemName: "gearshape"),
                        enabled: activePlacementState == nil
                    ) {
                        showingSettings = true
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        // dimmed rather than disabled: the drag being dimmed for
                        // starts here, and disabling would cancel it mid-gesture
                        let dimmed = activePlacementState != nil

                        emojiTextField
                            .modifier(EmojiButton(color: Palette.yellow, dimmed: dimmed))

                        ForEach(recentEmojisStore.recentEmojis, id: \.self) {
                            emoji in
                            Text(emoji.stringValue)
                                .gesture(
                                    makePaletteDragGesture(emoji: emoji)
                                )
                                .modifier(EmojiButton(color: Palette.pink, dimmed: dimmed))
                        }
                    }
                }
                .scrollClipDisabled()
            }.padding()

            if let dragState = activePlacementState, let canvasFrame {
                placementGlyph(dragState.placement)
                    .position(
                        dragState.placement.position * canvasFrame.height
                            + canvasFrame.origin
                    )
                    .opacity(dragState.placement.hasValidPosition ? 0.8 : 0.5)
                    // ignores safe area so that status bar and dynamic island to impact placement
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.purple)
        .confirmationDialog("Settings", isPresented: $showingSettings) {
            Button("Clear", role: .destructive) {
                placementService.apply(.clear)
            }
            Button("Log out", role: .destructive) {
                logout?()
            }
        }
    }
}

#Preview {
    CanvasView(
        placementService: DistributedStateMachineClient(
            localState: DistributedStateMachineLocalState(initialState: []),
            reduce: reduceCanvas(state:action:)
        ),
        logout: nil
    )
}
