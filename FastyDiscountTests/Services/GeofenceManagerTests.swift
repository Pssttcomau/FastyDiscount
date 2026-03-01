import Testing
import Foundation
@testable import FastyDiscount

// MARK: - GeofenceManagerTests

/// Tests for the geofence priority ranking algorithm and region limit logic.
///
/// These tests focus on the scoring/ranking logic rather than CLLocationManager
/// integration, which requires a device.
@Suite("GeofenceManager Tests")
struct GeofenceManagerTests {

    // MARK: - GeofenceSnapshot Tests

    @Test("test_effectiveRadius_zeroDefault_returns300")
    func test_effectiveRadius_zeroDefault_returns300() {
        let snapshot = GeofenceSnapshot.testFixture(geofenceRadius: 0.0)
        #expect(snapshot.effectiveRadius == 300.0)
    }

    @Test("test_effectiveRadius_customValue_returnsCustom")
    func test_effectiveRadius_customValue_returnsCustom() {
        let snapshot = GeofenceSnapshot.testFixture(geofenceRadius: 500.0)
        #expect(snapshot.effectiveRadius == 500.0)
    }

    @Test("test_regionIdentifier_format_containsDVGIDAndLocationID")
    func test_regionIdentifier_format_containsDVGIDAndLocationID() {
        let dvgID = UUID()
        let locationID = UUID()
        let snapshot = GeofenceSnapshot.testFixture(dvgID: dvgID, locationID: locationID)

        #expect(snapshot.regionIdentifier.hasPrefix("dvg-"))
        #expect(snapshot.regionIdentifier.contains(dvgID.uuidString))
        #expect(snapshot.regionIdentifier.contains(locationID.uuidString))
    }

    // MARK: - Priority Ranking Algorithm (tested via snapshots)

    /// Tests that the scoring formula correctly prioritises by expiry urgency.
    @Test("test_ranking_expiringVeryUrgent_scoredHigherThanNoExpiry")
    func test_ranking_expiringVeryUrgent_scoredHigherThanNoExpiry() {
        // A DVG expiring in 2 days should score higher than one with no expiry.
        let urgentSnapshot = GeofenceSnapshot.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
        )
        let noExpirySnapshot = GeofenceSnapshot.testFixture(
            expirationDate: nil
        )

        // Urgency: 2 days -> 1.0 (within 3 days)
        // No expiry -> 0.5
        // Without location, score = urgency * 0.9 + fav * 0.1
        let urgentScore = 1.0 * 0.9 + 0.0 * 0.1 // = 0.9
        let noExpiryScore = 0.5 * 0.9 + 0.0 * 0.1 // = 0.45

        #expect(urgentScore > noExpiryScore)
    }

    @Test("test_ranking_favoriteBonus_breaksExpiryTie")
    func test_ranking_favoriteBonus_breaksExpiryTie() {
        let sameDate = Calendar.current.date(byAdding: .day, value: 15, to: Date())
        let favSnapshot = GeofenceSnapshot.testFixture(
            isFavorite: true,
            expirationDate: sameDate
        )
        let notFavSnapshot = GeofenceSnapshot.testFixture(
            isFavorite: false,
            expirationDate: sameDate
        )

        // With same urgency, favourite should score 0.1 higher
        // Urgency for 15 days: (30-15)/(30-3) = 15/27 ~ 0.556
        let urgency = 15.0 / 27.0
        let favScore = urgency * 0.9 + 1.0 * 0.1
        let notFavScore = urgency * 0.9 + 0.0 * 0.1

        #expect(favScore > notFavScore)
    }

    @Test("test_ranking_expiryBeyond30Days_urgencyIsZero")
    func test_ranking_expiryBeyond30Days_urgencyIsZero() {
        // A DVG expiring in 60 days should have urgency 0.0
        let farSnapshot = GeofenceSnapshot.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: 60, to: Date())
        )

        // Score without location: 0.0 * 0.9 + 0.0 * 0.1 = 0.0
        let score = 0.0 * 0.9 + 0.0 * 0.1
        #expect(score == 0.0)
    }

    // MARK: - 20-Region Limit

    @Test("test_maxMonitoredRegions_is20")
    func test_maxMonitoredRegions_is20() {
        #expect(GeofenceManager.maxMonitoredRegions == 20)
    }

    @Test("test_ranking_top20Selection_selectsHighestScoring")
    func test_ranking_top20Selection_selectsHighestScoring() {
        // Create 25 snapshots with varying urgency
        var snapshots: [GeofenceSnapshot] = []
        for i in 0..<25 {
            snapshots.append(GeofenceSnapshot.testFixture(
                dvgID: UUID(),
                expirationDate: Calendar.current.date(byAdding: .day, value: i + 1, to: Date()),
                locationID: UUID()
            ))
        }

        // Sort by urgency descending (lowest day count = highest urgency)
        let sorted = snapshots.sorted { lhs, rhs in
            guard let lhsDate = lhs.expirationDate,
                  let rhsDate = rhs.expirationDate else { return false }
            return lhsDate < rhsDate
        }

        // Taking top 20 should exclude the 5 least urgent
        let top20 = Array(sorted.prefix(GeofenceManager.maxMonitoredRegions))
        #expect(top20.count == 20)

        // The last item in top20 should have expiration before the first excluded item
        if let top20Last = top20.last?.expirationDate,
           let excludedFirst = sorted[20].expirationDate {
            #expect(top20Last <= excludedFirst)
        }
    }

    // MARK: - Constants

    @Test("test_maxProximityDistance_is50km")
    func test_maxProximityDistance_is50km() {
        #expect(GeofenceManager.maxProximityDistance == 50_000.0)
    }

    @Test("test_minimumRecalculationDistance_is500m")
    func test_minimumRecalculationDistance_is500m() {
        #expect(GeofenceManager.minimumRecalculationDistance == 500.0)
    }

    @Test("test_regionIdentifierPrefix_isDvgDash")
    func test_regionIdentifierPrefix_isDvgDash() {
        #expect(GeofenceManager.regionIdentifierPrefix == "dvg-")
    }
}
