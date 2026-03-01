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
                    .font(Theme.Typography.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("FastyDiscount")
                        .font(Theme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("Your discount companion")
                        .font(Theme.Typography.body)
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
                    // Use the system-provided SignInWithAppleButton for App Store branding compliance.
                    // The completion result is routed through AuthViewModel → AuthenticationService.
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await viewModel.handleAuthorization(result)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .disabled(viewModel.isSigningIn)
                }

                Text("By signing in, you agree to use this app\nin accordance with Apple's terms of service.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("By signing in, you agree to use this app in accordance with Apple's terms of service.")
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
