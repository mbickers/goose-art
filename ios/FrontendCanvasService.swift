import SwiftUI

struct LocalState {
    let deviceSequenceNumber: Int
    let placements: [Placement]
    let unsyncedActions: [SequencedAction]
}

@Observable class FrontendCanvasService {
    private let canvasClient: CanvasClient?
    private let persistState: ((LocalState) -> Void)?

    private var localState: LocalState

    init(
        canvasClient: CanvasClient? = nil,
        initialState: LocalState? = nil,
        persistState: ((LocalState) -> Void)? = nil
    ) {
        self.canvasClient = canvasClient
        self.persistState = persistState
        self.localState =
            initialState
            ?? LocalState(
                deviceSequenceNumber: 0,
                placements: [],
                unsyncedActions: []
            )

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
        canvasClient?.updateActionsToSend(localState.unsyncedActions)
    }

    private func update(localState: LocalState) {
        self.localState = localState
        persistState?(localState)
    }

    var placements: [Placement] {
        var placements = localState.placements
        for sequencedAction in localState.unsyncedActions {
            switch sequencedAction.action {
            case .clear:
                placements = []
            case .remove(let id):
                placements = placements.filter { placement in
                    placement.id != id
                }
            case .upsert(let newPlacement):
                placements = placements.filter { placement in
                    placement.id != newPlacement.id
                }
                placements.append(newPlacement)
            }
        }
        return placements
    }

    func upsertPlacement(_ placement: Placement) {
        action(.upsert(placement: placement))
    }

    func remove(placementId: String) {
        action(.remove(placementId: placementId))
    }

    func clear() {
        action(.clear)
    }

    private func action(_ action: Action) {
        let deviceSequenceNumber = localState.deviceSequenceNumber + 1
        let unsyncedActions =
            localState.unsyncedActions
            + [
                SequencedAction(
                    action: action,
                    deviceSequenceNumber: deviceSequenceNumber
                )
            ]
        update(
            localState: LocalState(
                deviceSequenceNumber: deviceSequenceNumber,
                placements: localState.placements,
                unsyncedActions: unsyncedActions
            )
        )
        canvasClient?.updateActionsToSend(unsyncedActions)
    }

    func serverUpdate(
        greatestSeenDeviceSequenceNumber: Int,
        placements: [Placement]
    ) {
        update(
            localState: LocalState(
                // avoid server rejecting actions if client crashes after sending an update
                deviceSequenceNumber: max(
                    localState.deviceSequenceNumber,
                    greatestSeenDeviceSequenceNumber
                ),
                placements: placements,
                unsyncedActions: localState.unsyncedActions.filter {
                    sequencedAction in
                    sequencedAction.deviceSequenceNumber
                        > greatestSeenDeviceSequenceNumber
                }
            )
        )
    }
}
