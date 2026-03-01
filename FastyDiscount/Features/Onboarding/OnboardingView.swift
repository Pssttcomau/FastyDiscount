import SwiftUI

// MARK: - OnboardingView

/// Full-screen onboarding container shown on first launch.
///
/// Uses a `TabView` with `.tabViewStyle(.page)` for horizontal paging
/// between three onboarding screens. Completion and skip both call
/// `viewModel.completeOnboarding()` then notify the parent via the
/// `onComplete` callback so the root view can update its state.
struct OnboardingView: View {

    // MARK: - State

    @State private var viewModel = OnboardingViewModel()

    /// Called when the user completes or skips onboarding.
    var onComplete: () -> Void

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button row
                skipRow

                // Paged content
                TabView(selection: $viewModel.currentPageIndex) {
                    ForEach(OnboardingPage.allCases, id: \.rawValue) { page in
                        pageContent(for: page)
                            .tag(page.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Note: no extra .animation modifier here — .page style has its own
                // built-in paging animation; adding one causes double-animation/stutter.

                // Bottom controls
                bottomControls
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Skip Row

    private var skipRow: some View {
        HStack {
            Spacer()
            Button("Skip") {
                viewModel.skip()
                onComplete()
            }
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .accessibilityLabel("Skip onboarding")
            .accessibilityHint("Go directly to the main app")
        }
    }

    // MARK: - Page Content

    @ViewBuilder
    private func pageContent(for page: OnboardingPage) -> some View {
        // Pass currentPageIndex so each page can gate its animation on whether
        // it is the actually-visible page. With .page TabViewStyle all pages are
        // rendered at startup, so .onAppear fires for every page simultaneously.
        switch page {
        case .valueProp:
            ValuePropPage(currentPageIndex: $viewModel.currentPageIndex)
        case .features:
            FeaturesPage(currentPageIndex: $viewModel.currentPageIndex)
        case .addFirst:
            AddFirstPage(currentPageIndex: $viewModel.currentPageIndex,
                         onActionSelected: handleAddFirstAction)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Page indicator dots
            pageIndicator

            // Next / Get Started button
            if viewModel.isOnLastPage {
                // "Get Started" lets users complete onboarding without choosing
                // a specific action on Screen 3.
                getStartedButton
            } else {
                nextButton
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var pageIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<viewModel.totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == viewModel.currentPageIndex
                          ? Theme.Colors.primary
                          : Theme.Colors.border)
                    .frame(width: index == viewModel.currentPageIndex ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: viewModel.currentPageIndex)
            }
        }
        .accessibilityLabel("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages)")
        .accessibilityHint("Swipe left or right to navigate between pages")
    }

    private var nextButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.nextPage()
            }
        } label: {
            Text("Next")
                .font(Theme.Typography.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .accessibilityLabel("Next page")
        .accessibilityHint("Go to the next onboarding screen")
    }

    /// Shown on Screen 3 — completes onboarding without selecting a specific action.
    private var getStartedButton: some View {
        Button {
            viewModel.completeOnboarding()
            onComplete()
        } label: {
            Text("Get Started")
                .font(Theme.Typography.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .accessibilityLabel("Get started")
        .accessibilityHint("Complete onboarding and go to the dashboard")
    }

    // MARK: - Add First Action Handler

    private func handleAddFirstAction(_ action: AddFirstAction) {
        // Store the pending action BEFORE calling onComplete so the parent
        // can read it immediately when the fullScreenCover is dismissed.
        OnboardingPendingAction.shared.pendingAction = action
        viewModel.completeOnboarding()
        onComplete()
    }
}

// MARK: - OnboardingPendingAction

/// Stores the action selected on Screen 3 so the parent view can
/// navigate to the correct destination after onboarding is dismissed.
@Observable
@MainActor
final class OnboardingPendingAction {
    static let shared = OnboardingPendingAction()

    var pendingAction: AddFirstAction?

    private init() {}
}

// MARK: - AddFirstAction

/// The three options available on Screen 3.
enum AddFirstAction: Sendable {
    case scan
    case importEmail
    case addManually
}

// MARK: - ValuePropPage (Screen 1)

private struct ValuePropPage: View {

    @State private var illustrationOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    /// Binding to the parent's currentPageIndex so we know when this page is active.
    @Binding var currentPageIndex: Int

    private var isCurrentPage: Bool { currentPageIndex == OnboardingPage.valueProp.rawValue }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Hero illustration
                heroIllustration
                    .opacity(illustrationOpacity)
                    .animation(.easeIn(duration: 0.5).delay(0.1), value: illustrationOpacity)

                // Title and subtitle
                VStack(spacing: Theme.Spacing.md) {
                    Text(OnboardingPage.valueProp.title)
                        .font(Theme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(OnboardingPage.valueProp.subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .offset(y: contentOffset)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: contentOffset)

                // Benefit bullets
                benefitBullets
                    .offset(y: contentOffset)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: contentOffset)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
        }
        // .onChange fires only when this page becomes the visible one, avoiding the
        // problem where all .onAppear callbacks fire simultaneously at startup.
        .onChange(of: isCurrentPage, initial: true) { _, visible in
            guard visible else { return }
            illustrationOpacity = 1
            contentOffset = 0
        }
    }

    private var heroIllustration: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.primary.opacity(0.12))
                .frame(width: 200, height: 200)

            Circle()
                .fill(Theme.Colors.primary.opacity(0.08))
                .frame(width: 160, height: 160)

            Image(systemName: "tag.fill")
                .font(Theme.Typography.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Theme.Colors.primary)
                .symbolEffect(.pulse)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }

    private var benefitBullets: some View {
        VStack(spacing: Theme.Spacing.md) {
            BenefitRow(
                icon: "checkmark.seal.fill",
                iconColor: Theme.Colors.success,
                title: "Never miss an expiry",
                description: "Get notified before your discounts expire."
            )
            BenefitRow(
                icon: "bolt.fill",
                iconColor: Theme.Colors.accent,
                title: "Scan in seconds",
                description: "Camera and email scanning add discounts instantly."
            )
            BenefitRow(
                icon: "location.fill",
                iconColor: Theme.Colors.primary,
                title: "Alerts near stores",
                description: "Know when you're close to a store where a discount applies."
            )
        }
    }
}

// MARK: - FeaturesPage (Screen 2)

private struct FeaturesPage: View {

    @State private var illustrationOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    /// Binding to the parent's currentPageIndex so we know when this page is active.
    @Binding var currentPageIndex: Int

    private var isCurrentPage: Bool { currentPageIndex == OnboardingPage.features.rawValue }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Hero illustration
                featuresIllustration
                    .opacity(illustrationOpacity)
                    .animation(.easeIn(duration: 0.5).delay(0.1), value: illustrationOpacity)

                // Title and subtitle
                VStack(spacing: Theme.Spacing.md) {
                    Text(OnboardingPage.features.title)
                        .font(Theme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(OnboardingPage.features.subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .offset(y: contentOffset)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: contentOffset)

                // Feature cards
                featureCards
                    .offset(y: contentOffset)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: contentOffset)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
        }
        // .onChange fires only when this page becomes the visible one, avoiding the
        // problem where all .onAppear callbacks fire simultaneously at startup.
        .onChange(of: isCurrentPage, initial: true) { _, visible in
            guard visible else { return }
            illustrationOpacity = 1
            contentOffset = 0
        }
    }

    private var featuresIllustration: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accent.opacity(0.12))
                .frame(width: 200, height: 200)

            Circle()
                .fill(Theme.Colors.accent.opacity(0.08))
                .frame(width: 160, height: 160)

            Image(systemName: "sparkles")
                .font(Theme.Typography.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Theme.Colors.accent)
                .symbolEffect(.variableColor)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }

    private var featureCards: some View {
        VStack(spacing: Theme.Spacing.md) {
            FeatureCard(
                icon: "camera.fill",
                iconColor: Theme.Colors.primary,
                backgroundColor: Theme.Colors.primary.opacity(0.1),
                title: "Camera Scanning",
                description: "Point your camera at any barcode, QR code, or printed coupon to capture it instantly."
            )
            FeatureCard(
                icon: "envelope.fill",
                iconColor: Theme.Colors.accent,
                backgroundColor: Theme.Colors.accent.opacity(0.1),
                title: "Email Import",
                description: "Connect your inbox to automatically find and import discount codes from promotional emails."
            )
            FeatureCard(
                icon: "location.fill",
                iconColor: Theme.Colors.success,
                backgroundColor: Theme.Colors.success.opacity(0.1),
                title: "Location Alerts",
                description: "Get a notification when you're near a store where one of your saved discounts applies."
            )
        }
    }
}

// MARK: - AddFirstPage (Screen 3)

private struct AddFirstPage: View {

    @State private var illustrationOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    /// Binding to the parent's currentPageIndex so we know when this page is active.
    @Binding var currentPageIndex: Int

    var onActionSelected: (AddFirstAction) -> Void

    private var isCurrentPage: Bool { currentPageIndex == OnboardingPage.addFirst.rawValue }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Hero illustration
                addFirstIllustration
                    .opacity(illustrationOpacity)
                    .animation(.easeIn(duration: 0.5).delay(0.1), value: illustrationOpacity)

                // Title and subtitle
                VStack(spacing: Theme.Spacing.md) {
                    Text(OnboardingPage.addFirst.title)
                        .font(Theme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(OnboardingPage.addFirst.subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .offset(y: contentOffset)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: contentOffset)

                // Action options
                actionOptions
                    .offset(y: contentOffset)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: contentOffset)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
        }
        // .onChange fires only when this page becomes the visible one, avoiding the
        // problem where all .onAppear callbacks fire simultaneously at startup.
        .onChange(of: isCurrentPage, initial: true) { _, visible in
            guard visible else { return }
            illustrationOpacity = 1
            contentOffset = 0
        }
    }

    private var addFirstIllustration: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.primary.opacity(0.12))
                .frame(width: 200, height: 200)

            Circle()
                .fill(Theme.Colors.primary.opacity(0.08))
                .frame(width: 160, height: 160)

            Image(systemName: "plus.circle.fill")
                .font(Theme.Typography.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Theme.Colors.primary)
                .symbolEffect(.bounce)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }

    private var actionOptions: some View {
        VStack(spacing: Theme.Spacing.md) {
            AddOptionButton(
                icon: "camera.fill",
                iconColor: .white,
                iconBackground: Theme.Colors.primary,
                title: "Scan a Barcode",
                description: "Use your camera to scan a barcode or QR code",
                action: { onActionSelected(.scan) }
            )

            AddOptionButton(
                icon: "envelope.fill",
                iconColor: .white,
                iconBackground: Theme.Colors.accent,
                title: "Import from Email",
                description: "Scan your inbox for discount codes",
                action: { onActionSelected(.importEmail) }
            )

            AddOptionButton(
                icon: "square.and.pencil",
                iconColor: .white,
                iconBackground: Theme.Colors.secondary,
                title: "Add Manually",
                description: "Type in a code, name, or other details",
                action: { onActionSelected(.addManually) }
            )
        }
    }
}

// MARK: - Reusable Sub-Views

/// A benefit row used on Screen 1 with an icon, title, and description.
private struct BenefitRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

/// A feature card used on Screen 2 with a coloured icon and description.
private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(backgroundColor)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: icon)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

/// An interactive option button used on Screen 3.
private struct AddOptionButton: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let description: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(iconBackground)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: icon)
                            .font(Theme.Typography.title3)
                            .foregroundStyle(iconColor)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(description)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityAddTraits(.isButton)
    }
}
