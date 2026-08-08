import SwiftUI

struct LoginView: View {
    let authenticationService: AuthenticationService
    @State private var userIdInput: String = ""

    private func performLogin() {
        authenticationService.login(userId: userIdInput)
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
                TextField("User ID", text: $userIdInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 300)
                    .submitLabel(.go)
                    .onSubmit(performLogin)

                Button("Login", action: performLogin)
                    .frame(maxWidth: 300)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    LoginView(authenticationService: AuthenticationService())
}
