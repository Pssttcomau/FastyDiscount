import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.fastydiscount.shared"
    static let iCloudContainerIdentifier = "iCloud.com.fastydiscount.app"
    static let bundleIdentifier = "com.fastydiscount.app"

    enum DeepLink {
        static let scheme = "fastydiscount"
        static let dvgPath = "dvg"
    }

    // MARK: - AdMob

    enum AdMob {
        // MARK: Test Ad Unit IDs
        // Replace with real production ad unit IDs before App Store submission.
        // Real IDs are provisioned in the Google AdMob console (https://admob.google.com).

        /// Test banner ad unit ID (Google-provided, safe for development builds).
        /// Production: replace with your app-specific banner ad unit ID.
        static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"

        /// Test interstitial ad unit ID (Google-provided, safe for development builds).
        /// Production: replace with your app-specific interstitial ad unit ID.
        static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    }

    enum PassKit {
        /// Pass Type ID registered in Apple Developer portal.
        /// Must match the identifier provisioned in the developer account.
        static let passTypeIdentifier = "pass.com.fastydiscount.dvg"

        /// Apple Developer Team Identifier.
        /// Replace with the actual team ID from the developer account.
        static let teamIdentifier = "XXXXXXXXXX"

        /// Default organization name displayed on passes when no store name is available.
        static let organizationName = "FastyDiscount"
    }
}
