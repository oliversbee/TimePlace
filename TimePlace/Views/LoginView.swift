import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Framed")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white) // Restored to white

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 32)

            if let error = auth.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await auth.login(email: email, password: password) }
            } label: {
                Group {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Text("Log In").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .disabled(email.isEmpty || password.isEmpty || auth.isLoading)

            // Add this below your Log In button:
            Text("By logging in, you agree to our Terms of Service and Privacy Policy.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 10)

            Spacer()
            Spacer()
        }
        .background(Color.black.ignoresSafeArea()) // Restored to black
        .preferredColorScheme(.dark) // NEW: Forces the keyboard and text fields to be dark too
    }
}