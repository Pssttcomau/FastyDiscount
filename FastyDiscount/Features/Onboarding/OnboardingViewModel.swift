import SwiftUI

// MARK: - OnboardingPage

/// Represents a single onboarding screen with its content data.
enum OnboardingPage: Int, CaseIterable, Sendable {
    case valueProp = 0
    case features  = 1
    case addFirst  = 2

    var title: String {
        switch self {
        case .valueProp: "Never Waste a Discount Again"
        case .features:  "Everything You Need"
        case .addFirst:  "Add Your First Discount"
        }
    }

    var subtitle: String {
        switch self {
        case .valueProp:
            "FastyDiscount keeps all your discounts, vouchers, and gift cards in one place — always ready when you need them."
        case .features:
            "Three powerful ways to save every discount before it slips away."
        case .addFirst:
            "Choose how you'd like to get started. You can always add more later."
        }
    }

    var symbolName: String {
        switch self {
        case .valueProp: "tag.fill"
        case .features:  "sparkles"
        case .addFirst:  "plus.circle.fill"
        }
    }
}

// MARK: - OnboardingViewModel

/// Manages onboarding flow state including the current page and completion tracking.
///
/// Completion is persisted in `UserDefaults` under the key `hasCompletedOnboarding`.
/// Both "Skip" and finishing the flow (or adding a first discount) mark onboarding complete.
@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - Published State

    /// The index of the currently visible onboarding page.
    var currentPageIndex: Int = 0

    // MARK: - Computed Properties

    var currentPage: OnboardingPage {
        OnboardingPage(rawValue: currentPageIndex) ?? .valueProp
    }

    var isOnLastPage: Bool {
        currentPageIndex == OnboardingPage.allCases.count - 1
    }

    var totalPages: Int {
        OnboardingPage.allCases.count
    }

    // MARK: - UserDefaults Key

    private static let completedKey = "hasCompletedOnboarding"

    // MARK: - Persistence

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    // MARK: - Actions

    /// Advances to the next page if not on the last page.
    func nextPage() {
        guard currentPageIndex < totalPages - 1 else { return }
        currentPageIndex += 1
    }

    /// Marks onboarding as complete and updates UserDefaults.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    /// Skips onboarding immediately, marking it complete.
    func skip() {
        completeOnboarding()
    }
}
