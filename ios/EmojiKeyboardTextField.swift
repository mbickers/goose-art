import SwiftUI
import UIKit

private final class EmojiInputTextField: UITextField {
    // overriding the input mode is the only way to open the emoji keyboard directly:
    // SwiftUI's TextField has no direct equivalent, and UIKeyboardType has no emoji case

    override var textInputMode: UITextInputMode? {
        // nil when the user has removed the emoji keyboard in Settings. In this case,
        // UIKit uses default keyboard
        return UITextInputMode.activeInputModes.first { mode in
            mode.primaryLanguage == "emoji"
        }
    }
}

struct EmojiKeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiKeyboardTextField

        init(parent: EmojiKeyboardTextField) {
            self.parent = parent
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = EmojiInputTextField()
        textField.delegate = context.coordinator
        textField.textAlignment = .center
        textField.returnKeyType = .done
        textField.font = .systemFont(ofSize: EmojiButton.glyphSize)
        textField.tintColor = UIColor(Palette.darkPurple)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }
}
