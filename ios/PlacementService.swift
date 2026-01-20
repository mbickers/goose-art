import SwiftUI

@Observable class PlacementService {
    private(set) var placements: [Placement]
    var canUndo: Bool { !placements.isEmpty }

    init() {
        self.placements = []
    }

    func place(_ placement: Placement) {
        placements.append(placement)
    }
    
    func undo() {
        placements.removeLast()
    }
    
    func clear() {
        placements.removeAll()
    }
}
