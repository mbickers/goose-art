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

struct Placement: Codable {
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
}

enum Action {
    case clear
    case undo(id: String)
    case place(Placement)
}

struct SequencedAction {
    let action: Action
    let deviceSequenceNumber: Int
}

