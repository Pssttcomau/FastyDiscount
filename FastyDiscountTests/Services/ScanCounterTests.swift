import Testing
import Foundation
@testable import FastyDiscount

// MARK: - ScanCounterTests

@Suite("ScanCounter Tests")
@MainActor
struct ScanCounterTests {

    @Test("test_recordScan_incrementsTotalCount")
    func test_recordScan_incrementsTotalCount() {
        let counter = ScanCounter()
        let initial = counter.totalScanCount
        counter.recordScan()
        #expect(counter.totalScanCount == initial + 1)
    }

    @Test("test_recordScan_incrementsScansSinceLastAd")
    func test_recordScan_incrementsScansSinceLastAd() {
        let counter = ScanCounter()
        counter.resetInterstitialFlag()
        counter.recordScan()
        #expect(counter.scansSinceLastAd == 1)
    }

    @Test("test_recordScan_thresholdReached_shouldShowInterstitial")
    func test_recordScan_thresholdReached_shouldShowInterstitial() {
        let counter = ScanCounter()
        counter.resetInterstitialFlag()

        for _ in 0..<ScanCounter.interstitialThreshold {
            counter.recordScan()
        }

        #expect(counter.shouldShowInterstitial == true)
    }

    @Test("test_recordScan_belowThreshold_shouldNotShowInterstitial")
    func test_recordScan_belowThreshold_shouldNotShowInterstitial() {
        let counter = ScanCounter()
        counter.resetInterstitialFlag()

        for _ in 0..<(ScanCounter.interstitialThreshold - 1) {
            counter.recordScan()
        }

        #expect(counter.shouldShowInterstitial == false)
    }

    @Test("test_resetInterstitialFlag_resetsCountAndFlag")
    func test_resetInterstitialFlag_resetsCountAndFlag() {
        let counter = ScanCounter()
        // Trigger the interstitial
        counter.resetInterstitialFlag()
        for _ in 0..<ScanCounter.interstitialThreshold {
            counter.recordScan()
        }
        #expect(counter.shouldShowInterstitial == true)

        counter.resetInterstitialFlag()

        #expect(counter.shouldShowInterstitial == false)
        #expect(counter.scansSinceLastAd == 0)
    }

    @Test("test_interstitialThreshold_is5")
    func test_interstitialThreshold_is5() {
        #expect(ScanCounter.interstitialThreshold == 5)
    }
}
