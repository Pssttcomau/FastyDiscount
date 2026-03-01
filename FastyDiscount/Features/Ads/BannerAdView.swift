import SwiftUI
import UIKit

// MARK: - BannerAdView
//
// A SwiftUI banner ad component.
//
// When the GoogleMobileAds SDK is available (after Xcode SPM resolution):
//   - Replace `MockBannerAdUIView` with `GADBannerView`.
//   - Uncomment the `#if canImport(GoogleMobileAds)` block below.
//
// For now, this renders a mock placeholder so the layout and integration
// can be verified without the SDK dependency.

/// A SwiftUI-compatible banner ad container.
///
/// Shows nothing when `adService.isAdFree` is `true`.
/// In development (mock), renders a labelled placeholder.
/// In production (real SDK), renders a `GADBannerView`.
///
/// After every 10th banner ad impression, shows an `AdUpgradeBanner`
/// suggestion prompting the user to remove ads. The banner is inline,
/// dismissible, and non-modal.
///
/// Place at the bottom of a view hierarchy, inside a `VStack`.
struct BannerAdView: View {

    // MARK: - Dependencies

    var adUnitID: String
    var adService: any AdService

    // MARK: - Upgrade Banner State

    /// Whether the inline "Remove Ads" suggestion banner is currently visible.
    @State private var showUpgradeBanner: Bool = false

    /// Number of impressions between upgrade suggestion threshold checks (every 10th).
    private static let upgradeSuggestionThreshold = 10

    // MARK: - Banner dimensions

    /// Standard banner height (320x50 equivalent — used by GADAdSizeBanner).
    private let bannerHeight: CGFloat = 50

    // MARK: - Body

    var body: some View {
        if adService.isAdFree {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                // Inline upgrade suggestion banner — shown every 10th impression.
                AdUpgradeBanner(isVisible: $showUpgradeBanner)
                    .animation(.easeInOut(duration: 0.25), value: showUpgradeBanner)

                // The banner ad itself.
                bannerContent
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerHeight)
            }
            .onAppear {
                recordImpressionAndLoadAd()
            }
        }
    }

    // MARK: - Private Helpers

    /// Records a banner ad impression and loads the ad.
    /// If this is the 10th impression (or a multiple thereof), shows the upgrade banner.
    private func recordImpressionAndLoadAd() {
        adService.loadBannerAd(adUnitID: adUnitID)
        adService.adImpressionCount += 1

        if adService.adImpressionCount % Self.upgradeSuggestionThreshold == 0 {
            withAnimation(.easeInOut(duration: 0.25)) {
                showUpgradeBanner = true
            }
        }
    }

    // MARK: - Banner Content

    @ViewBuilder
    private var bannerContent: some View {
        // When the real GoogleMobileAds SDK is integrated, replace this block:
        //
        // #if canImport(GoogleMobileAds)
        // RealBannerAdRepresentable(adUnitID: adUnitID)
        //     .frame(height: bannerHeight)
        // #else
        MockBannerAdRepresentable()
            .frame(height: bannerHeight)
        // #endif
    }
}

// MARK: - MockBannerAdRepresentable

/// UIViewRepresentable placeholder for development.
/// Renders a labelled rectangle to indicate where the banner ad will appear.
private struct MockBannerAdRepresentable: UIViewRepresentable {

    func makeUIView(context: Context) -> MockBannerAdUIView {
        MockBannerAdUIView()
    }

    func updateUIView(_ uiView: MockBannerAdUIView, context: Context) {}
}

// MARK: - MockBannerAdUIView

private final class MockBannerAdUIView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.systemGray5

        let label = UILabel()
        label.text = "Advertisement (Test)"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])

        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 0.5
    }
}

// MARK: - Real Banner Ad Representable (Uncomment when SDK is available)
//
// #if canImport(GoogleMobileAds)
// import GoogleMobileAds
//
// private struct RealBannerAdRepresentable: UIViewRepresentable {
//
//     let adUnitID: String
//
//     func makeCoordinator() -> Coordinator {
//         Coordinator()
//     }
//
//     func makeUIView(context: Context) -> GADBannerView {
//         let banner = GADBannerView(adSize: GADAdSizeBanner)
//         banner.adUnitID = adUnitID
//         banner.delegate = context.coordinator
//
//         // Find the root view controller to present the banner from
//         if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//            let rootVC = windowScene.windows.first?.rootViewController {
//             banner.rootViewController = rootVC
//         }
//
//         banner.load(GADRequest())
//         return banner
//     }
//
//     func updateUIView(_ uiView: GADBannerView, context: Context) {}
//
//     // MARK: - Coordinator
//
//     final class Coordinator: NSObject, GADBannerViewDelegate {
//         func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
//             // Gracefully suppress the view on load failure — the SwiftUI frame
//             // collapses to zero if the GADBannerView itself reports no ad.
//         }
//     }
// }
// #endif

// MARK: - Preview

#if DEBUG
#Preview("BannerAdView - Mock") {
    VStack {
        Spacer()
        Text("Content goes here")
        Spacer()
        BannerAdView(
            adUnitID: AppConstants.AdMob.bannerAdUnitID,
            adService: MockAdMobService()
        )
    }
}

#Preview("BannerAdView - Ad Free") {
    let service = MockAdMobService()
    // Ad-free state is driven by UserDefaults; simulate by checking isAdFree
    return VStack {
        Spacer()
        Text("Ad-free content")
        Spacer()
        BannerAdView(
            adUnitID: AppConstants.AdMob.bannerAdUnitID,
            adService: service
        )
        Text("(Banner hidden when ad-free)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
#endif
