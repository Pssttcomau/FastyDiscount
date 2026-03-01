import Foundation
import os

// MARK: - ScanCounter
//
// Tracks the cumulative number of scans performed (camera or email) and
// determines when an interstitial ad should be shown.
//
// Usage:
//   Call `recordScan()` whenever a scan operation completes successfully.
//   Subscribe to `shouldShowInterstitial` to know when to present the ad.
//   Call `resetInterstitialFlag()` after the interstitial has been displayed.

@Observable
@MainActor
final class ScanCounter {

    // MARK: - Singleton

    static let shared = ScanCounter()

    // MARK: - Constants

    /// Number of scans between interstitial ad presentations.
    static let interstitialThreshold = 5

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let totalScanCount = "com.fastydiscount.totalScanCount"
        static let scansSinceLastAd = "com.fastydiscount.scansSinceLastAd"
    }

    // MARK: - State

    /// Total lifetime scan count (camera + email).
    private(set) var totalScanCount: Int

    /// Number of scans since the last interstitial was shown.
    private(set) var scansSinceLastAd: Int

    /// Set to `true` when the interstitial threshold is crossed.
    /// The presenter should observe this and reset it after showing the ad.
    private(set) var shouldShowInterstitial: Bool = false

    // MARK: - Logger

    private let logger = Logger(subsystem: "com.fastydiscount", category: "ScanCounter")

    // MARK: - Init

    init() {
        totalScanCount = UserDefaults.standard.integer(forKey: Keys.totalScanCount)
        scansSinceLastAd = UserDefaults.standard.integer(forKey: Keys.scansSinceLastAd)
    }

    // MARK: - Public API

    /// Records a completed scan and evaluates whether to show an interstitial.
    func recordScan() {
        totalScanCount += 1
        scansSinceLastAd += 1

        UserDefaults.standard.set(totalScanCount, forKey: Keys.totalScanCount)
        UserDefaults.standard.set(scansSinceLastAd, forKey: Keys.scansSinceLastAd)

        logger.debug("Scan recorded. Total: \(self.totalScanCount), Since last ad: \(self.scansSinceLastAd)")

        if scansSinceLastAd >= ScanCounter.interstitialThreshold {
            shouldShowInterstitial = true
            logger.info("Interstitial threshold reached (\(ScanCounter.interstitialThreshold) scans).")
        }
    }

    /// Called after the interstitial has been presented (or skipped because
    /// the user is ad-free). Resets the counter so the next cycle begins.
    func resetInterstitialFlag() {
        shouldShowInterstitial = false
        scansSinceLastAd = 0
        UserDefaults.standard.set(0, forKey: Keys.scansSinceLastAd)
        logger.debug("Interstitial flag reset. Scan cycle restarting.")
    }
}
