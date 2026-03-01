import Foundation
import SwiftData

// MARK: - UITestDataSeeder

/// Seeds deterministic mock data into the SwiftData context for UI testing.
///
/// Only compiled in DEBUG builds. Called when the app is launched with the
/// `-UITestMode` launch argument, ensuring tests have predictable data to interact with.
#if DEBUG
@MainActor
enum UITestDataSeeder {

    // MARK: - Seed

    /// Inserts a fixed set of test DVGs into the given context.
    /// Clears any existing data first to ensure a clean, deterministic state.
    static func seed(into context: ModelContext) {
        // Clear existing DVG data
        let existingDVGDescriptor = FetchDescriptor<DVG>()
        if let existing = try? context.fetch(existingDVGDescriptor) {
            for dvg in existing {
                context.delete(dvg)
            }
        }

        // Insert test DVGs
        for dvg in makeSeedDVGs() {
            context.insert(dvg)
        }

        try? context.save()
    }

    // MARK: - Test Data

    /// Returns a fixed set of DVGs covering multiple types and statuses.
    static func makeSeedDVGs() -> [DVG] {
        let calendar = Calendar.current
        let now = Date()

        return [
            // Active discount code from Target — used in search/filter tests
            DVG(
                title: "20% Off Everything",
                code: "SAVE20",
                dvgType: .discountCode,
                storeName: "Target",
                originalValue: 20.0,
                discountDescription: "20% off all items",
                expirationDate: calendar.date(byAdding: .day, value: 30, to: now),
                source: .manual,
                status: .active,
                isFavorite: false
            ),

            // Active voucher from Nike — used in filter/type tests
            DVG(
                title: "Free Shipping Voucher",
                code: "FREESHIP",
                dvgType: .voucher,
                storeName: "Nike",
                originalValue: 15.0,
                discountDescription: "Free shipping on any order",
                expirationDate: calendar.date(byAdding: .day, value: 14, to: now),
                source: .manual,
                status: .active,
                isFavorite: true
            ),

            // Active gift card from Apple — used in detail view tests
            DVG(
                title: "Apple Gift Card",
                code: "AAPL-GIFT-1234",
                dvgType: .giftCard,
                storeName: "Apple",
                originalValue: 100.0,
                remainingBalance: 75.50,
                discountDescription: "Apple Store gift card",
                expirationDate: nil,
                source: .manual,
                status: .active,
                notes: "Birthday gift from family",
                isFavorite: false
            ),

            // Active loyalty points from Starbucks — used in type filter tests
            DVG(
                title: "Starbucks Stars",
                code: "SBUX-LOYALTY",
                dvgType: .loyaltyPoints,
                storeName: "Starbucks",
                originalValue: 0.0,
                pointsBalance: 250,
                discountDescription: "Starbucks Rewards points",
                source: .manual,
                status: .active,
                isFavorite: false
            ),

            // Expiring soon (within 7 days) — used in dashboard expiring section
            DVG(
                title: "Weekend Sale 30% Off",
                code: "WKND30",
                dvgType: .discountCode,
                storeName: "H&M",
                originalValue: 30.0,
                discountDescription: "30% off all weekend purchases",
                expirationDate: calendar.date(byAdding: .day, value: 3, to: now),
                source: .manual,
                status: .active,
                isFavorite: false
            ),

            // Used DVG — appears in history tab
            DVG(
                title: "ASOS 10% Off",
                code: "ASOS10",
                dvgType: .discountCode,
                storeName: "ASOS",
                originalValue: 10.0,
                discountDescription: "10% off first order",
                expirationDate: calendar.date(byAdding: .day, value: -5, to: now),
                source: .manual,
                status: .used,
                lastModified: calendar.date(byAdding: .day, value: -2, to: now) ?? now
            ),

            // Expired DVG — appears in history tab
            DVG(
                title: "Black Friday Voucher",
                code: "BF2024",
                dvgType: .voucher,
                storeName: "Amazon",
                originalValue: 50.0,
                discountDescription: "Black Friday special voucher",
                expirationDate: calendar.date(byAdding: .day, value: -30, to: now),
                source: .manual,
                status: .expired,
                lastModified: calendar.date(byAdding: .day, value: -30, to: now) ?? now
            )
        ]
    }
}
#endif
