import SwiftUI
import AuthenticationServices

// MARK: - SignInView

/// The authentication gate shown on app launch if the user is not signed in.
/// Follows Apple Human Interface Guidelines:
/// - Centered Sign in with Apple button
/// - Minimal UI with app branding
/// - No extraneous content
struct SignInView: View {

    @State private var viewModel: AuthViewModel

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("FastyDiscount")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("Your discount companion")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Sign in section
            VStack(spacing: 20) {
                if viewModel.isSigningIn {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                } else {
                    // Use a custom button wrapping SignInWithAppleButton appearance
                    // The actual auth flow is handled by ASAuthorizationController in AuthenticationService.
                    Button {
                        Task {
                            await viewModel.signIn()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.body.weight(.semibold))
                            Text("Sign in with Apple")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Sign in with Apple")
                    .disabled(viewModel.isSigningIn)
                }

                Text("By signing in, you agree to use this app\nin accordance with Apple's terms of service.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .alert(
            "Sign In Failed",
            isPresented: $viewModel.hasError
        ) {
            Button("Try Again") {
                Task { await viewModel.signIn() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Sign In View") {
    SignInView(
        viewModel: AuthViewModel(
            authService: MockAuthenticationService(isAuthenticated: false)
        )
    )
}
#endif
