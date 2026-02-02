import SwiftUI

@Observable class FrontendCanvasService {
    let userId: String
    private var deviceSequenceNumber: Int

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

    private var unsyncedActions: [SequencedAction] = []
    private var syncedPlacements: [Placement] = []

    init() {
        self.syncedPlacements = []
        self.unsyncedActions = []
        self.userId = "max"
        self.deviceSequenceNumber = 0
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
    }

    func serverUpdate(
        greatestSeenDeviceSequenceNumber: Int,
        placements: [Placement]
    ) {
        unsyncedActions.removeAll { sequencedAction in
            sequencedAction.deviceSequenceNumber <= greatestSeenDeviceSequenceNumber
        }
        // avoid server rejecting actions if client crashes after sending an update
        deviceSequenceNumber = max(deviceSequenceNumber, greatestSeenDeviceSequenceNumber)
        syncedPlacements = placements
    }
}
