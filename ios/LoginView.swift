import SwiftUI

struct LoginView: View {
    let authenticationService: AuthenticationService
    @State private var codeInput: String = ""
    @State private var loggingIn = false

    private func performLogin() {
        loggingIn = true
        Task {
            await authenticationService.login(token: codeInput)
            loggingIn = false
        }
    }

    var body: some View {
        // TODO: fix look
        VStack(spacing: 20) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("Not Authenticated")
                .font(.title)
                .fontWeight(.bold)

            switch authenticationService.state {
            case .unauthenticated(let reason?):
                Text(reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            default:
                EmptyView()
            }

            VStack(spacing: 12) {
                TextField("Access code", text: $codeInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 300)
                    .submitLabel(.go)
                    .onSubmit(performLogin)

                Button(action: performLogin) {
                    if loggingIn {
                        ProgressView()
                    } else {
                        Text("Login")
                    }
                }
                .frame(maxWidth: 300)
                .buttonStyle(.borderedProminent)
                .disabled(codeInput.isEmpty || loggingIn)
            }
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    LoginView(authenticationService: AuthenticationService(baseURL: nil))
}
