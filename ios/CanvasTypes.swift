import CoreGraphics
import Foundation

struct Emoji: Equatable, Codable, Hashable {
    let value: Character

    init?(_ value: Character) {
        guard value.isEmoji else { return nil }
        self.value = value
    }

    var stringValue: String { String(value) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let char = string.first, let emoji = Emoji(char) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid emoji character"
            )
        }
        self.value = emoji.value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

extension Character {
    fileprivate var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmojiPresentation
            || (unicodeScalars.count > 1 && firstScalar.properties.isEmoji)
    }
}

struct Placement: Codable, Equatable {
    let emoji: Emoji
    let position: CGPoint
    let scale: CGFloat
    let rotation: CGFloat
    let isMirrored: Bool
    let id: String

    var hasValidPosition: Bool {
        return CGRect(x: 0, y: 0, width: 1, height: 1).contains(position)
    }

    func with(
        position: CGPoint? = nil,
        scale: CGFloat? = nil,
        rotation: CGFloat? = nil,
        isMirrored: Bool? = nil
    ) -> Placement {
        return Placement(
            emoji: emoji,
            position: position ?? self.position,
            scale: scale ?? self.scale,
            rotation: rotation ?? self.rotation,
            isMirrored: isMirrored ?? self.isMirrored,
            id: id
        )
    }
}

// CGPoint encodes itself as a bare [x, y] array, but the server and every canvas already
// stored on a device speak {"x": …, "y": …}. Position is the one field that can't be
// synthesized, and living in an extension keeps the memberwise init synthesized.
extension Placement {
    private struct Coordinates: Codable {
        let x: CGFloat
        let y: CGFloat
    }

    private enum CodingKeys: String, CodingKey {
        case emoji, position, scale, rotation, isMirrored, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinates = try container.decode(Coordinates.self, forKey: .position)
        self.init(
            emoji: try container.decode(Emoji.self, forKey: .emoji),
            position: CGPoint(x: coordinates.x, y: coordinates.y),
            scale: try container.decode(CGFloat.self, forKey: .scale),
            rotation: try container.decode(CGFloat.self, forKey: .rotation),
            isMirrored: try container.decode(Bool.self, forKey: .isMirrored),
            id: try container.decode(String.self, forKey: .id)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(emoji, forKey: .emoji)
        try container.encode(Coordinates(x: position.x, y: position.y), forKey: .position)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(isMirrored, forKey: .isMirrored)
        try container.encode(id, forKey: .id)
    }
}

enum CanvasAction: Codable {
    case clear
    case remove(placementId: String)
    case upsert(placement: Placement)

    private enum CodingKeys: String, CodingKey {
        case type
        case placement
        case placementId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "upsert":
            let placement = try container.decode(Placement.self, forKey: .placement)
            self = .upsert(placement: placement)
        case "remove":
            let placementId = try container.decode(String.self, forKey: .placementId)
            self = .remove(placementId: placementId)
        case "clear":
            self = .clear
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .upsert(let placement):
            try container.encode("upsert", forKey: .type)
            try container.encode(placement, forKey: .placement)
        case .remove(let placementId):
            try container.encode("remove", forKey: .type)
            try container.encode(placementId, forKey: .placementId)
        case .clear:
            try container.encode("clear", forKey: .type)
        }
    }
}

func reduceCanvas(state: [Placement], action: CanvasAction) -> [Placement] {
    switch action {
    case .clear:
        return []
    case .remove(let placementId):
        return state.filter { placement in
            placement.id != placementId
        }
    case .upsert(let newPlacement):
        // an upserted placement moves to the top of the z-order
        return state.filter { placement in
            placement.id != newPlacement.id
        } + [newPlacement]
    }
}
