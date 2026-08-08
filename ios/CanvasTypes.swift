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
    let userId: String
    let id: String

    var hasValidPosition: Bool {
        return CGRect(x: 0, y: 0, width: 1, height: 1).contains(position)
    }

    func with(
        position: CGPoint? = nil,
        scale: CGFloat? = nil,
        rotation: CGFloat? = nil,
        isMirrored: Bool? = nil,
        userId: String? = nil,
        id: String? = nil,
    ) -> Placement {
        return Placement(
            emoji: emoji,
            position: position ?? self.position,
            scale: scale ?? self.scale,
            rotation: rotation ?? self.rotation,
            isMirrored: isMirrored ?? self.isMirrored,
            userId: userId ?? self.userId,
            id: id ?? self.id
        )
    }

    enum CodingKeys: String, CodingKey {
        case emoji
        case position
        case scale
        case rotation
        case isMirrored
        case userId
        case id
    }

    init(
        emoji: Emoji, position: CGPoint, scale: CGFloat, rotation: CGFloat, isMirrored: Bool,
        userId: String, id: String
    ) {
        self.emoji = emoji
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.isMirrored = isMirrored
        self.userId = userId
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.emoji = try container.decode(Emoji.self, forKey: .emoji)

        let positionDict = try container.decode([String: CGFloat].self, forKey: .position)
        guard let x = positionDict["x"], let y = positionDict["y"] else {
            throw DecodingError.dataCorruptedError(
                forKey: .position,
                in: container,
                debugDescription: "Position must have x and y values"
            )
        }
        self.position = CGPoint(x: x, y: y)

        self.scale = try container.decode(CGFloat.self, forKey: .scale)
        self.rotation = try container.decode(CGFloat.self, forKey: .rotation)
        self.isMirrored = try container.decode(Bool.self, forKey: .isMirrored)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.id = try container.decode(String.self, forKey: .id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(emoji, forKey: .emoji)
        try container.encode(["x": position.x, "y": position.y], forKey: .position)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(isMirrored, forKey: .isMirrored)
        try container.encode(userId, forKey: .userId)
        try container.encode(id, forKey: .id)
    }
}

enum Action {
    case clear
    case undo(placementId: String)
    case place(Placement)
}

struct SequencedAction: Codable {
    let action: Action
    let deviceSequenceNumber: Int

    private enum CodingKeys: String, CodingKey {
        case action
        case deviceSequenceNumber
    }

    private enum ActionCodingKeys: String, CodingKey {
        case type
        case placement
        case placementId
    }

    init(action: Action, deviceSequenceNumber: Int) {
        self.action = action
        self.deviceSequenceNumber = deviceSequenceNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionContainer = try container.nestedContainer(
            keyedBy: ActionCodingKeys.self,
            forKey: .action
        )

        let type = try actionContainer.decode(String.self, forKey: .type)
        switch type {
        case "place":
            let placement = try actionContainer.decode(Placement.self, forKey: .placement)
            self.action = .place(placement)
        case "undo":
            let placementId = try actionContainer.decode(String.self, forKey: .placementId)
            self.action = .undo(placementId: placementId)
        case "clear":
            self.action = .clear
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: actionContainer,
                debugDescription: "Unknown action type: \(type)"
            )
        }

        self.deviceSequenceNumber = try container.decode(Int.self, forKey: .deviceSequenceNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var actionContainer = container.nestedContainer(
            keyedBy: ActionCodingKeys.self,
            forKey: .action
        )

        switch action {
        case .place(let placement):
            try actionContainer.encode("place", forKey: .type)
            try actionContainer.encode(placement, forKey: .placement)
        case .undo(let placementId):
            try actionContainer.encode("undo", forKey: .type)
            try actionContainer.encode(placementId, forKey: .placementId)
        case .clear:
            try actionContainer.encode("clear", forKey: .type)
        }

        try container.encode(deviceSequenceNumber, forKey: .deviceSequenceNumber)
    }
}
