import Foundation
import CoreGraphics

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

fileprivate extension Character {
    var isEmoji: Bool {
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

    init(
        emoji: Emoji,
        position: CGPoint,
        scale: CGFloat,
        rotation: CGFloat,
        isMirrored: Bool
    ) {
        self.emoji = emoji
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.isMirrored = isMirrored
    }

    var hasValidPosition: Bool {
        return CGRect(x: 0, y: 0, width: 1, height: 1).contains(position)
    }
}
