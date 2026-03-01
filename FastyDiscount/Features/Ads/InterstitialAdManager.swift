import SwiftUI
import UIKit
import os

// MARK: - InterstitialAdManager
//
// Coordinates interstitial ad display by observing `ScanCounter.shouldShowInterstitial`
// and delegating to `AdService.showInterstitialAd`.
//
// Usage:
//   Attach `.interstitialAdOverlay(adService:)` view modifier to a top-level view
//   (e.g., ContentView or each tab root view).
//
// How it works:
//   1. `ScanCounter.shared.recordScan()` is called after each scan completes.
//   2. When the count reaches the threshold (5), `shouldShowInterstitial` becomes `true`.
//   3. `InterstitialAdManager` detects this via `.onChange(of:)` and shows the ad.
//   4. After showing (or skipping for ad-free users), the counter resets.

@Observable
@MainActor
final class InterstitialAdManager {

    // MARK: - Dependencies

    private let adService: any AdService
    private let scanCounter: ScanCounter
    private let logger = Logger(subsystem: "com.fastydiscount", category: "InterstitialAdManager")

    // MARK: - State

    /// Whether the interstitial ad is currently being presented.
    private(set) var isPresenting: Bool = false

    // MARK: - Init

    init(
        adService: any AdService,
        scanCounter: ScanCounter = .shared
    ) {
        self.adService = adService
        self.scanCounter = scanCounter
    }

    // MARK: - Public API

    /// Pre-loads an interstitial so it is ready to show when needed.
    func preloadInterstitial() async {
        guard !adService.isAdFree else { return }
        await adService.loadInterstitialAd(adUnitID: AppConstants.AdMob.interstitialAdUnitID)
        logger.debug("Interstitial preloaded.")
    }

    /// Called when `ScanCounter.shouldShowInterstitial` becomes `true`.
    /// Presents the ad if ready; always resets the scan counter.
    func handleInterstitialTrigger() async {
        defer {
            scanCounter.resetInterstitialFlag()
        }

        guard !adService.isAdFree else {
            logger.debug("Skipping interstitial — user is ad-free.")
            return
        }

        // Attempt to find the top-most UIViewController to present from
        guard let viewController = topViewController() else {
            logger.warning("Cannot show interstitial — no root view controller found.")
            return
        }

        if adService.isInterstitialReady {
            isPresenting = true
            adService.showInterstitialAd(from: viewController)
            logger.info("Interstitial ad presented.")
        } else {
            logger.warning("Interstitial triggered but ad not ready. Skipping this cycle.")
        }

        // Reload for the next cycle
        await adService.loadInterstitialAd(adUnitID: AppConstants.AdMob.interstitialAdUnitID)
        isPresenting = false
    }

    // MARK: - Private Helpers

    /// Walks the UIViewController hierarchy to find the topmost presented controller.
    private func topViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }

        var topVC: UIViewController = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - View Modifier

/// Attaches interstitial ad observation to any SwiftUI view.
///
/// Example usage on a tab root:
/// ```swift
/// DashboardView()
///     .interstitialAdOverlay(adService: adService)
/// ```
struct InterstitialAdModifier: ViewModifier {

    @State private var manager: InterstitialAdManager
    private let scanCounter: ScanCounter

    init(adService: any AdService, scanCounter: ScanCounter = .shared) {
        _manager = State(initialValue: InterstitialAdManager(adService: adService, scanCounter: scanCounter))
        self.scanCounter = scanCounter
    }

    func body(content: Content) -> some View {
        content
            .task {
                await manager.preloadInterstitial()
            }
            .onChange(of: scanCounter.shouldShowInterstitial) { _, shouldShow in
                guard shouldShow else { return }
                Task {
                    await manager.handleInterstitialTrigger()
                }
            }
    }
}

extension View {
    /// Attaches interstitial ad management to this view.
    ///
    /// The modifier observes `ScanCounter.shared` and presents the interstitial
    /// when the scan threshold is reached.
    func interstitialAdOverlay(adService: any AdService) -> some View {
        modifier(InterstitialAdModifier(adService: adService))
    }
}
