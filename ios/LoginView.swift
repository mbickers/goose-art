import SwiftUI

struct LoginView: View {
    let authenticationService: AuthenticationService
    @State private var userIdInput: String = ""
    
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
                    .frame(maxWidth: 300)
                
                Button(action: {
                    Task {
                        await authenticationService.login(userId: userIdInput)
                    }
                }) {
                    Text("Login")
                        .frame(maxWidth: 300)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userIdInput.isEmpty)
            }
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    LoginView(authenticationService: AuthenticationService())
}

