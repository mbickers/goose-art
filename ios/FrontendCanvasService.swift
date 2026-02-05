import SwiftUI

@Observable class FrontendCanvasService {
    let userId: String
    private let canvasClient: CanvasClient?
    private var deviceSequenceNumber: Int

    private var unsyncedActions: [SequencedAction] = []
    private var syncedPlacements: [Placement] = []

    init(canvasClient: CanvasClient? = nil) {
        self.canvasClient = canvasClient
        self.userId = canvasClient?.userId ?? "anonymous"
        self.syncedPlacements = []
        self.unsyncedActions = []
        self.deviceSequenceNumber = 0

        if let message = canvasClient?.mostRecentServerMessage {
            serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                placements: message.placements
            )
        }
        canvasClient?.subscribeToServerMessages { [weak self] message in
            self?.serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                placements: message.placements
            )
        }
        canvasClient?.updateActionsToSend(unsyncedActions)
    }

    var placements: [Placement] {
        var placements = syncedPlacements
        for sequencedAction in unsyncedActions {
            switch sequencedAction.action {
            case .clear:
                placements = []
            case .undo(let id):
                placements = placements.filter { placement in
                    placement.id != id
                }
            case .place(let newPlacement):
                placements.append(newPlacement)
            }
        }
        return placements
    }
    var undoablePlacementId: String? {
        placements.last(where: { placement in placement.userId == userId })?.id
    }

    func place(_ placement: Placement) {
        action(
            .place(placement.with(userId: userId, id: UUID().uuidString))
        )
    }

    func undo() {
        guard let undoablePlacementId else { return }
        action(.undo(placementId: undoablePlacementId))
    }

    func clear() {
        action(.clear)
    }

    private func action(_ action: Action) {
        deviceSequenceNumber += 1
        let sequencedAction = SequencedAction(
            action: action,
            deviceSequenceNumber: deviceSequenceNumber
        )
        unsyncedActions.append(sequencedAction)
        canvasClient?.updateActionsToSend(unsyncedActions)
    }

    func serverUpdate(
        greatestSeenDeviceSequenceNumber: Int,
        placements: [Placement]
    ) {
        unsyncedActions.removeAll { sequencedAction in
            sequencedAction.deviceSequenceNumber
                <= greatestSeenDeviceSequenceNumber
        }
        // avoid server rejecting actions if client crashes after sending an update
        deviceSequenceNumber = max(
            deviceSequenceNumber,
            greatestSeenDeviceSequenceNumber
        )
        syncedPlacements = placements
    }
}
