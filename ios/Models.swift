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

    func with(userId: String) -> Placement {
        return Placement(
            emoji: emoji,
            position: position,
            scale: scale,
            rotation: rotation,
            isMirrored: isMirrored,
            userId: userId
        )
    }

    var hasValidPosition: Bool {
        return CGRect(x: 0, y: 0, width: 1, height: 1).contains(position)
    }
}
