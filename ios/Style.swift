import SwiftUI

// namespaced rather than an `extension Color`, because the palette's natural names
// (blue, pink, purple, yellow) all collide with SwiftUI's built-in colors
enum Palette {
    static let blue = Color(hex: "8DE8E8")
    static let darkPurple = Color(hex: "2A053E")
    static let purple = Color(hex: "3D3E5A")
    static let yellow = Color(hex: "F4C77F")
    static let pink = Color(hex: "E8A5B3")
}

// every font in the app goes through this, so that .rounded reaches #Preview too,
// which a .fontDesign on the app's root view would miss
extension Font {
    static func rounded(size: CGFloat, weight: Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
}

struct RoundedBorder: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        content
            .clipShape(shape)
            .overlay(
                shape.stroke(Palette.darkPurple, lineWidth: lineWidth)
            )
            .padding(lineWidth / 2)
    }
}

private let buttonBorder = RoundedBorder(cornerRadius: 20, lineWidth: 6)

// the border sits above the dimming so it stays solid while the fill fades
struct ButtonSurface: ViewModifier {
    let color: Color
    let dimmed: Bool

    func body(content: Content) -> some View {
        content
            .background(color)
            .opacity(dimmed ? 0.5 : 1)
            .modifier(buttonBorder)
    }
}

struct EmojiButton: ViewModifier {
    let color: Color
    let dimmed: Bool

    func body(content: Content) -> some View {
        content
            .font(.rounded(size: 40))
            .frame(width: 60, height: 60)
            .modifier(ButtonSurface(color: color, dimmed: dimmed))
    }
}

// full width, 40 tall, yellow, dimmed when it can't be used
struct CustomButton: View {
    // icons carry heavier weight than text does at the same size
    enum Content {
        case icon(systemName: String)
        case text(String)
        case progress
    }

    private let content: Content
    private let action: () -> Void
    private let enabled: Bool

    init(content: Content, enabled: Bool = true, action: @escaping () -> Void) {
        self.content = content
        self.enabled = enabled
        self.action = action
    }

    @ViewBuilder private var label: some View {
        switch content {
        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.rounded(size: 20, weight: .heavy))
        case .text(let text):
            Text(text)
                .font(.rounded(size: 20, weight: .semibold))
        case .progress:
            ProgressView()
        }
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundColor(Palette.darkPurple)
                .tint(Palette.darkPurple)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .modifier(ButtonSurface(color: Palette.yellow, dimmed: !enabled))
        }
        .disabled(!enabled)
    }
}
