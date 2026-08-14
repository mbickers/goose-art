import SwiftUI
import UIKit

private struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: CGFloat  // radians
}

private struct ActivePlacementState {
    enum Source {
        case palette
        case canvas
    }

    let placement: Placement
    let secondTouchState: SecondTouchState?
    let source: Source

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

private func lastEmojiInString(_ string: String) -> Emoji? {
    return string.compactMap { Emoji($0) }.last
}

// an emoji as it left the drag: where it landed, and the size and angle the user pinched
// and rotated the preview to, both in the canvas's own points
private struct DroppedEmoji {
    let emoji: Emoji
    let location: CGPoint
    let height: CGFloat
    let rotation: CGFloat
}

// UIKit reports that pinch and rotation in exactly one place — the preview it offers back
// as the drop lands — and SwiftUI's DropDelegate has no hook for it, which is the reason
// the canvas hosts a UIDropInteraction rather than using .dropDestination or .onDrop.
private struct EmojiDropTarget: UIViewRepresentable {
    let onDrop: (DroppedEmoji) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onDrop = onDrop
    }

    func makeCoordinator() -> EmojiDropCoordinator {
        return EmojiDropCoordinator(onDrop: onDrop)
    }
}

private final class EmojiDropCoordinator: NSObject, UIDropInteractionDelegate {
    var onDrop: (DroppedEmoji) -> Void

    // UIKit offers the preview after performDrop but before the item provider delivers,
    // so it is held here and read once the string finally arrives
    private var droppedPreview: UITargetedDragPreview? = nil

    init(onDrop: @escaping (DroppedEmoji) -> Void) {
        self.onDrop = onDrop
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        canHandle session: any UIDropSession
    ) -> Bool {
        return session.canLoadObjects(ofClass: String.self)
    }

    // text dragged out of a field suggests .move, and a destination that proposes nothing
    // back is refused with the grey forbidden badge. a drop here adds a placement, and
    // must never edit the text it came from, so it is always a copy
    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidUpdate session: any UIDropSession
    ) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        previewForDropping item: UIDragItem,
        withDefault defaultPreview: UITargetedDragPreview
    ) -> UITargetedDragPreview? {
        droppedPreview = defaultPreview
        // nil fades the preview out in place, handing off to the placement springing in
        return nil
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        performDrop session: any UIDropSession
    ) {
        guard let view = interaction.view else { return }
        let location = session.location(in: view)

        _ = session.loadObjects(ofClass: String.self) { [weak self] strings in
            guard let self, let preview = self.droppedPreview,
                let emoji = strings.compactMap(lastEmojiInString).last
            else { return }
            self.droppedPreview = nil

            let transform = preview.target.transform
            self.onDrop(
                DroppedEmoji(
                    emoji: emoji,
                    location: location,
                    height: preview.size.height * transform.scaleFactor(),
                    rotation: transform.rotationAngle()
                )
            )
        }
    }
}

// one feel for a placement settling into place, whether it arrives (a transition) or
// moves (keyframes), which SwiftUI has no single mechanism for
private let placementSpring = Spring(duration: 0.3, bounce: 0.45)

// minimum is an EmojiButton's 60 plus the 6 its border adds, so a column is never
// wide enough for a button it can't actually fit
private let paletteColumns = [GridItem(.adaptive(minimum: 66), spacing: 4)]

struct CanvasView: View {
    let placementService: DistributedStateMachineClient<[Placement], CanvasAction>
    let userId: String
    let logout: (() -> Void)?

    @State private var recentEmojisStore = RecentEmojiService()

    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var activePlacementState: ActivePlacementState? = nil
    @State private var canvasFrame: CGRect? = nil
    @State private var showingSettings = false
    @AppStorage(MessageSound.enabledDefaultsKey) private var soundEffectsEnabled = true

    // two coordinate systems meet here: screen points, which is what gestures report in
    // the .global space, and canvas points, the unit square a Placement is stored in
    private func toCanvasPoint(screenPoint: CGPoint) -> CGPoint? {
        guard let canvasFrame else { return nil }
        return (screenPoint - canvasFrame.origin).safeDivide(
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
            guard
                let canvasPoint = toCanvasPoint(screenPoint: value.location)
            else { return }
            let activePlacementState =
                activePlacementState
                ?? ActivePlacementState(
                    placement: makePlacement(canvasPoint),
                    secondTouchState: nil,
                    source: source
                )
            self.activePlacementState = activePlacementState.with(
                placement:
                    activePlacementState.placement.with(
                        position: canvasPoint
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
            makePlacement: { canvasPoint in
                Placement(
                    emoji: emoji,
                    position: canvasPoint,
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

    // the drop reports the preview's real on-screen height, so the emoji keeps the size it
    // was dragged at without the canvas having to guess a text height. mirroring is the one
    // thing a drag can't carry, and the button already covers it
    private func dropEmoji(_ drop: DroppedEmoji) {
        guard let canvasFrame else { return }

        placementService.apply(
            .upsert(
                placement: Placement(
                    emoji: drop.emoji,
                    position: drop.location.safeDivide(canvasFrame.width),
                    scale: (drop.height / canvasFrame.height).clamped(
                        to: Placement.scaleRange
                    ),
                    rotation: drop.rotation,
                    isMirrored: false,
                    id: UUID().uuidString
                )
            )
        )
        recentEmojisStore.emojiUsed(drop.emoji)
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
                let startCanvasPoint = toCanvasPoint(
                    screenPoint: value.startLocation
                ),
                let currentCanvasPoint = toCanvasPoint(
                    screenPoint: value.location
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
                        initialOffset: startCanvasPoint
                            - dragState.placement.position,
                        baseScale: dragState.placement.scale,
                        baseRotation: dragState.placement.rotation
                    )
                )
                return
            }

            let currentOffset =
                currentCanvasPoint - dragState.placement.position

            // how far the second finger has to travel to scale the placement, and the
            // floor on where it started from, so that a second touch landing on the
            // placement itself doesn't divide by ~0
            let clampedInitialOffsetNorm = max(
                secondTouchState.initialOffset
                    .norm(),
                0.01
            )
            let clampedScale =
                (secondTouchState.baseScale
                * 1.5 * currentOffset.norm()
                / clampedInitialOffsetNorm).clamped(
                    to: Placement.scaleRange
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
    private func placementGlyph(_ placement: Placement, canvasFrame: CGRect) -> some View {
        Text(placement.emoji.stringValue)
            .font(.rounded(size: canvasFrame.height * placement.scale))
            // the canvas proposes less width than the full-screen drag preview,
            // so without this a large glyph gets a narrower frame in one than
            // the other and .position centers them differently
            .fixedSize()
            .scaleEffect(x: placement.isMirrored ? -1 : 1, y: 1)
            .rotationEffect(Angle(radians: placement.rotation))
    }

    var body: some View {
        ZStack {
            // the whole page scrolls, so the palette grid can run off the bottom;
            // scrolling is off during a drag so the canvas can't move out from
            // under the placement being dropped onto it
            ScrollView(.vertical, showsIndicators: false) {
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
                                placementGlyph(placement, canvasFrame: canvasFrame)
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
                    // animate (only) new placements
                    .animation(
                        .spring(placementSpring),
                        value: Set(placementService.state.map(\.id))
                    )
                    .onGeometryChange(
                        for: CGRect.self,
                        of: { geometry in geometry.frame(in: .global) },
                        action: { frame in canvasFrame = frame }
                    )
                    // sits with .onGeometryChange, above the border's padding, so that a
                    // drop's coordinates are the same space the glyphs are placed in. a
                    // background rather than an overlay: SwiftUI hit-tests front to back,
                    // so the glyphs above keep their own pickup gestures
                    .background(EmojiDropTarget(onDrop: dropEmoji))
                    .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 500)

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

                    LazyVGrid(columns: paletteColumns, spacing: 4) {
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
                }.padding()
            }
            .scrollDisabled(activePlacementState != nil)

            if let dragState = activePlacementState, let canvasFrame {
                placementGlyph(dragState.placement, canvasFrame: canvasFrame)
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
            Button(soundEffectsEnabled ? "Turn off sound effects" : "Turn on sound effects") {
                soundEffectsEnabled.toggle()
            }
            Button("Log out \(userId)", role: .destructive) {
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
        userId: "max",
        logout: nil
    )
}
