struct Emoji: Equatable, Hashable {
    let value: Character

    init?(_ value: Character) {
        guard value.isEmoji else { return nil }
        self.value = value
    }

    var stringValue: String { String(value) }
}

fileprivate extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmojiPresentation
            || (unicodeScalars.count > 1 && firstScalar.properties.isEmoji)
    }
}

