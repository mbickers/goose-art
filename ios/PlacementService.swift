import SwiftUI

enum Action {
    case clear
    case undo
    case place(Placement)
}

extension Array {
    fileprivate func removingLastWhere(_ predicate: (Element) -> Bool)
        -> [Element]
    {
        guard let index = lastIndex(where: predicate) else { return self }
        var copy = self
        copy.remove(at: index)
        return copy
    }
}

@Observable class PlacementService {
    let userId: String
    var placements: [Placement] {
        var placements = syncedState
        for action in unsyncedActions {
            switch action {
            case .clear:
                placements = []
            case .undo:
                placements = placements.removingLastWhere { placement in
                    placement.userId == userId
                }
            case .place(let newPlacement):
                placements.append(newPlacement)
            }
        }
        return placements
    }
    var canUndo: Bool {
        placements.contains(where: { placement in placement.userId == userId })
    }

    private var unsyncedActions: [Action] = []
    private var syncedState: [Placement] = []

    init() {
        self.syncedState = []
        self.unsyncedActions = []
        self.userId = "max"
    }

    func place(_ placement: Placement) {
        unsyncedActions.append(.place(placement))
    }

    func undo() {
        unsyncedActions.append(Action.undo)
    }

    func clear() {
        unsyncedActions.append(Action.clear)
    }
}
