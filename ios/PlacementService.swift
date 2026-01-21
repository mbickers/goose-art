import SwiftUI

enum Action {
    case clear
    case undo(id: String)
    case place(Placement)
}

@Observable class PlacementService {
    let userId: String
    var placements: [Placement] {
        var placements = syncedState
        for action in unsyncedActions {
            switch action {
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

    private var unsyncedActions: [Action] = []
    private var syncedState: [Placement] = []

    init() {
        self.syncedState = []
        self.unsyncedActions = []
        self.userId = "max"
    }

    func place(_ placement: Placement) {
        unsyncedActions.append(
            .place(placement.with(userId: userId, id: UUID().uuidString))
        )
    }

    func undo() {
        guard let undoablePlacementId else { return }
        unsyncedActions.append(Action.undo(id: undoablePlacementId))
    }

    func clear() {
        unsyncedActions.append(Action.clear)
    }
}
