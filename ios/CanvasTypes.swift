import CoreGraphics
import Foundation

struct Emoji: Equatable, Codable, Hashable {
    private let value: Character

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
    // a placement lives in canvas coordinates: the unit square, with 1 the canvas's
    // side, so the same canvas renders identically at any size. scale is a fraction
    // of that side too
    static let scaleRange: ClosedRange<CGFloat> = 0.05...1

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

extension Placement {
    // By default, CGPoint encodes itself as a bare [x, y] array
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

struct CanvasState: Codable, Equatable {
    let title: String
    let placements: [Placement]

    static let empty = CanvasState(title: "", placements: [])
}

enum CanvasAction: Codable {
    case clear
    case remove(placementId: String)
    case setTitle(title: String)
    case upsert(placement: Placement)

    private enum CodingKeys: String, CodingKey {
        case type
        case placement
        case placementId
        case title
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
        case "setTitle":
            let title = try container.decode(String.self, forKey: .title)
            self = .setTitle(title: title)
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
        case .setTitle(let title):
            try container.encode("setTitle", forKey: .type)
            try container.encode(title, forKey: .title)
        case .clear:
            try container.encode("clear", forKey: .type)
        }
    }
}

func reduceCanvas(state: CanvasState, action: CanvasAction) -> CanvasState {
    switch action {
    case .clear:
        return .empty
    case .remove(let placementId):
        return CanvasState(
            title: state.title,
            placements: state.placements.filter { placement in
                placement.id != placementId
            }
        )
    case .setTitle(let title):
        return CanvasState(title: title, placements: state.placements)
    case .upsert(let newPlacement):
        // an upserted placement moves to the top of the z-order
        return CanvasState(
            title: state.title,
            placements: state.placements.filter { placement in
                placement.id != newPlacement.id
            } + [newPlacement]
        )
    }
}
