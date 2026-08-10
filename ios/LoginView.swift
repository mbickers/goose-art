import SwiftUI

struct LoginView: View {
    let authenticationService: AuthenticationService
    @State private var codeInput: String = ""
    @State private var loggingIn = false
    @FocusState private var codeFieldFocused: Bool

    private var canSubmit: Bool {
        return !codeInput.isEmpty && !loggingIn
    }

    private var failureReason: String? {
        guard case .unauthenticated(let reason) = authenticationService.state
        else { return nil }
        return reason
    }

    private func performLogin() {
        loggingIn = true
        Task {
            await authenticationService.login(token: codeInput)
            loggingIn = false
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("🦆🪿")
                .font(.rounded(size: 70))

            Text("goose art")
                .font(.rounded(size: 44, weight: .heavy))
                .foregroundColor(Palette.pink)

            if let failureReason {
                Text(failureReason)
                    .font(.rounded(size: 16, weight: .semibold))
                    .foregroundColor(Palette.pink)
                    .multilineTextAlignment(.center)
            }

            TextField(
                "",
                text: $codeInput,
                prompt: Text("access code").foregroundColor(Palette.darkPurple.opacity(0.5))
            )
            .focused($codeFieldFocused)
            .onAppear { codeFieldFocused = true }
            .tint(Palette.darkPurple)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit(performLogin)
            .font(.rounded(size: 20, weight: .semibold))
            .foregroundColor(Palette.darkPurple)
            .multilineTextAlignment(.center)
            .frame(height: 50)
            .modifier(ButtonSurface(color: Palette.yellow, dimmed: false))

            CustomButton(
                content: loggingIn ? .progress : .text("login"),
                enabled: canSubmit,
                action: performLogin
            )
        }
        .padding(30)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.purple)
    }
}

#Preview {
    LoginView(authenticationService: AuthenticationService(baseURL: nil))
}
