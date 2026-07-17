/*
 * Purpose: Email/password sign-in screen gating RootShell.
 * Inputs: user-entered email/password; SessionStore for the login call.
 * Outputs: none (mutates SessionStore.user on success).
 * Run: shown by RootShell when !SessionStore.isAuthenticated.
 */

import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("CaseRoom")
                    .font(.largeTitle.bold())

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                if let error = sessionStore.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)
            }
            .padding()
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await sessionStore.login(email: email, password: password)
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
