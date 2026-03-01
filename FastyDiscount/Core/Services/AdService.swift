import Foundation
import SwiftUI

// MARK: - AdService Protocol
//
// NOTE: Google Mobile Ads SDK dependency (SPM):
//   URL: https://github.com/googleads/swift-package-manager-google-mobile-ads
//   Package: GoogleMobileAds
// This must be added manually via Xcode: File > Add Package Dependencies.
// Once added, enable the real AdMobService by compiling with -DADMOB_ENABLED
// or by swapping MockAdMobService for AdMobService in the environment injection.

/// Protocol describing the ad service interface used throughout the app.
/// Abstracted so that:
///   - The real AdMobService (wrapping GoogleMobileAds) can be swapped in when
///     the SDK is available.
///   - Tests and previews use MockAdMobService without any SDK dependency.
@MainActor
protocol AdService: AnyObject {

    /// Whether the user has an active ad-free subscription.
    /// When `true`, no ads should be displayed.
    /// This is read from UserDefaults; TASK-040 (StoreKit 2) will write to it.
    var isAdFree: Bool { get }

    /// Loads a banner ad for the given ad unit ID.
    /// Should be called when the view hosting the banner appears.
    func loadBannerAd(adUnitID: String)

    /// Loads an interstitial ad into memory so it is ready to show.
    func loadInterstitialAd(adUnitID: String) async

    /// Shows the preloaded interstitial ad from the given UIViewController.
    /// Does nothing if the ad is not ready or `isAdFree` is `true`.
    func showInterstitialAd(from viewController: UIViewController)

    /// Whether the interstitial ad is loaded and ready to present.
    var isInterstitialReady: Bool { get }
}

// MARK: - UserDefaults Key

private extension String {
    static let adFreeKey = "com.fastydiscount.adFree"
}

// MARK: - MockAdMobService

/// Development/Preview implementation of `AdService`.
/// Simulates ad behaviour without importing GoogleMobileAds.
@Observable
@MainActor
final class MockAdMobService: AdService {

    // MARK: - AdService

    /// Whether the user has an active ad-free entitlement.
    /// Stored as a plain `@Observable` property so SwiftUI views track it reactively.
    /// `AppStoreKitService` updates this directly when a purchase is verified or revoked.
    /// The initial value is read from UserDefaults so the app starts in the correct state
    /// before StoreKit entitlement verification completes.
    var isAdFree: Bool = UserDefaults.standard.bool(forKey: .adFreeKey) {
        didSet { UserDefaults.standard.set(isAdFree, forKey: .adFreeKey) }
    }

    private(set) var isInterstitialReady: Bool = false

    func loadBannerAd(adUnitID: String) {
        // No-op in mock; banner view renders a placeholder instead.
    }

    func loadInterstitialAd(adUnitID: String) async {
        // Simulate a network delay for the mock
        try? await Task.sleep(for: .milliseconds(500))
        isInterstitialReady = true
    }

    func showInterstitialAd(from viewController: UIViewController) {
        guard !isAdFree, isInterstitialReady else { return }
        isInterstitialReady = false
        // In mock: schedule a reload after a short delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            isInterstitialReady = true
        }
    }
}

// MARK: - AdMobService (Real — requires GoogleMobileAds SDK)
//
// Enabled when GoogleMobileAds is linked. Add the SPM package in Xcode and
// the conditional compilation flag ADMOB_ENABLED (or rely on canImport).
//
// #if canImport(GoogleMobileAds)
// import GoogleMobileAds
//
// @Observable
// @MainActor
// final class AdMobService: NSObject, AdService {
//
//     var isAdFree: Bool {
//         UserDefaults.standard.bool(forKey: "com.fastydiscount.adFree")
//     }
//
//     private(set) var isInterstitialReady: Bool = false
//     private var interstitial: GADInterstitialAd?
//
//     func loadBannerAd(adUnitID: String) {
//         // Banner loading is handled inside BannerAdView via GADBannerView.
//     }
//
//     func loadInterstitialAd(adUnitID: String) async {
//         do {
//             interstitial = try await GADInterstitialAd.load(
//                 withAdUnitID: adUnitID,
//                 request: GADRequest()
//             )
//             isInterstitialReady = interstitial != nil
//         } catch {
//             isInterstitialReady = false
//         }
//     }
//
//     func showInterstitialAd(from viewController: UIViewController) {
//         guard !isAdFree, isInterstitialReady, let interstitial else { return }
//         interstitial.present(fromRootViewController: viewController)
//         isInterstitialReady = false
//         self.interstitial = nil
//     }
// }
// #endif
