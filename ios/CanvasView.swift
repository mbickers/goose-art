import SwiftUI
import UIKit

private struct SecondTouchState {
    let initialOffset: CGPoint
    let baseScale: CGFloat
    let baseRotation: CGFloat
}

private struct ActivePlacementState {
    enum Source {
        case palette
        case canvas
    }

    let placement: Placement
    let secondTouchState: SecondTouchState?
    let source: Source
    let behindId: String?

    func with(placement: Placement) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState,
            source: source,
            behindId: behindId
        )
    }

    func with(secondTouchState: SecondTouchState?) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState,
            source: source,
            behindId: behindId
        )
    }

    func with(behindId: String?) -> ActivePlacementState {
        return ActivePlacementState(
            placement: placement,
            secondTouchState: secondTouchState,
            source: source,
            behindId: behindId
        )
    }
}

private func lastEmojiInString(_ string: String) -> Emoji? {
    return string.compactMap { Emoji($0) }.last
}

private typealias EmojiDropHandler = (
    _ emoji: Emoji,
    // both in the drop view's coordinates
    _ itemPosition: CGPoint,
    _ itemHeight: CGFloat,
    _ itemRotation: CGFloat
) -> Void

private struct EmojiDropTarget: UIViewRepresentable {
    let onDrop: EmojiDropHandler

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

private let defaultDroppedItemHeight: CGFloat = 55

private final class EmojiDropCoordinator: NSObject, UIDropInteractionDelegate {
    var onDrop: EmojiDropHandler

    private var droppedPreview: UITargetedDragPreview? = nil
    private var droppedTransform: CGAffineTransform = .identity

    init(onDrop: @escaping EmojiDropHandler) {
        self.onDrop = onDrop
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        canHandle session: any UIDropSession
    ) -> Bool {
        return session.canLoadObjects(ofClass: String.self)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidUpdate session: any UIDropSession
    ) -> UIDropProposal {
        // a drag suggesting .move is refused with a forbidden badge unless something is
        // proposed back. a drop adds a placement and never edits its source, so: copy
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        previewForDropping item: UIDragItem,
        withDefault defaultPreview: UITargetedDragPreview
    ) -> UITargetedDragPreview? {
        droppedPreview = defaultPreview
        droppedTransform = item.unsafeExtractSuggestedTransform() ?? .identity
        // nil fades the preview out immediately
        return nil
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        performDrop session: any UIDropSession
    ) {
        guard let view = interaction.view else { return }
        let location = session.location(in: view)

        _ = session.loadObjects(ofClass: String.self) { [weak self] strings in
            guard let self else { return }

            // cleared even when nothing lands, so the next drop can't read this one's state
            let preview = self.droppedPreview
            let transform = self.droppedTransform
            self.droppedPreview = nil
            self.droppedTransform = .identity

            guard let emoji = strings.compactMap(lastEmojiInString).last else { return }

            self.onDrop(
                emoji,
                // a drag hangs off wherever it was grabbed, so the touch isn't the center
                preview?.target.center ?? location,
                (preview?.size.height ?? defaultDroppedItemHeight) * transform.scaleFactor(),
                transform.rotationAngle()
            )
        }
    }
}

private let placementSpring = Spring(duration: 0.3, bounce: 0.45)

struct CanvasView: View {
    let canvasService: DistributedStateMachineClient<CanvasState, CanvasAction>
    let userId: String
    let logout: (() -> Void)?

    @State private var recentEmojisStore = RecentEmojiService()

    @State private var emojiFieldValue: String = ""
    @FocusState private var emojiFieldFocused: Bool

    @State private var titleFieldValue: String = ""
    @FocusState private var titleFieldFocused: Bool

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
                    source: source,
                    behindId: nil
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

    private func dropEmoji(
        _ emoji: Emoji,
        itemPosition: CGPoint,
        itemHeight: CGFloat,
        itemRotation: CGFloat
    ) {
        guard let canvasFrame else { return }

        canvasService.apply(
            .upsert(
                placement: Placement(
                    emoji: emoji,
                    position: itemPosition.safeDivide(canvasFrame.width),
                    scale: (itemHeight / canvasFrame.height).clamped(
                        to: Placement.scaleRange
                    ),
                    rotation: itemRotation,
                    isMirrored: false,
                    id: UUID().uuidString
                ),
                behindId: nil
            )
        )
        recentEmojisStore.emojiUsed(emoji)
    }

    private func dropActivePlacement() {
        guard let state = activePlacementState else { return }
        activePlacementState = nil

        switch (state.source, state.placement.hasValidPosition) {
        case (.palette, true):
            canvasService.apply(
                .upsert(placement: state.placement, behindId: state.behindId)
            )
            recentEmojisStore.emojiUsed(state.placement.emoji)
        case (.canvas, true):
            canvasService.apply(
                .upsert(placement: state.placement, behindId: state.behindId)
            )
        case (.canvas, false):
            canvasService.apply(.remove(placementId: state.placement.id))
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
                // anchors on where the finger is now rather than value.startLocation:
                // the gesture's minimumDistance means it has already travelled by the
                // first callback, and anchoring behind it makes scale and rotation
                // jump by that much the instant the second touch registers
                self.activePlacementState = dragState.with(
                    secondTouchState: SecondTouchState(
                        initialOffset: currentCanvasPoint
                            - dragState.placement.position,
                        baseScale: dragState.placement.scale,
                        baseRotation: dragState.placement.rotation
                    )
                )
                return
            }

            let currentOffset =
                currentCanvasPoint - dragState.placement.position

            let clampedScale =
                (secondTouchState.baseScale
                + 2
                * (currentOffset.norm()
                    - secondTouchState.initialOffset
                    .norm()))
                .clamped(
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

    private func nextBehindIdCyclingUpwards(
        behindId: String?,
        draggedPlacementId: String
    ) -> String? {
        let otherIdsFromBottom = canvasService.state.placements
            .map(\.id)
            .filter { $0 != draggedPlacementId }
        guard let behindId else { return otherIdsFromBottom.first }
        guard let index = otherIdsFromBottom.firstIndex(of: behindId) else { return nil }
        return otherIdsFromBottom.dropFirst(index + 1).first
    }

    private var titleTextField: some View {
        TextField("", text: $titleFieldValue, prompt: Text.placeholder("name ye art"))
            .focused($titleFieldFocused)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { titleFieldFocused = false }
            .onChange(of: titleFieldFocused) { _, isFocused in
                guard !isFocused, titleFieldValue != canvasService.state.title else {
                    return
                }
                canvasService.apply(.setTitle(title: titleFieldValue))
            }
            .onChange(of: canvasService.state.title, initial: true) { _, title in
                titleFieldValue = title
            }
            .modifier(TextFieldSurface())
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
                                canvasService.state.placements,
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
                        value: Set(canvasService.state.placements.map(\.id))
                    )
                    .onGeometryChange(
                        for: CGRect.self,
                        of: { geometry in geometry.frame(in: .global) },
                        action: { frame in canvasFrame = frame }
                    )
                    // sits with .onGeometryChange, above the border's padding, so a drop's
                    // coordinates match the glyphs'. a background, not an overlay: SwiftUI
                    // hit-tests front to back, so glyphs keep their pickup gestures
                    .background(EmojiDropTarget(onDrop: dropEmoji))
                    .modifier(RoundedBorder(cornerRadius: 20, lineWidth: 6))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 500)

                    titleTextField

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
                            content: .icon(systemName: "square.3.layers.3d"),
                            enabled: activePlacementState != nil
                        ) {
                            if let dragState = activePlacementState {
                                activePlacementState = dragState.with(
                                    behindId: nextBehindIdCyclingUpwards(
                                        behindId: dragState.behindId,
                                        draggedPlacementId: dragState.placement.id
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

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 4)], spacing: 4) {
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
                canvasService.apply(.clear)
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
        canvasService: DistributedStateMachineClient(
            localState: DistributedStateMachineLocalState(initialState: .empty),
            reduce: reduceCanvas(state:action:)
        ),
        userId: "max",
        logout: nil
    )
}
