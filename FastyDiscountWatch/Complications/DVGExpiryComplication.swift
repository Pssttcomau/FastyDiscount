import WidgetKit
import SwiftUI

// MARK: - Complication Timeline Entry

/// A single point-in-time snapshot for the DVG expiry complication.
struct DVGExpiryEntry: TimelineEntry {
    let date: Date
    let nextDVG: WatchDVG?
    let daysRemaining: Int?

    /// Placeholder entry for the complication gallery.
    static var placeholder: DVGExpiryEntry {
        DVGExpiryEntry(
            date: Date(),
            nextDVG: WatchDVG(
                id: UUID(),
                title: "20% off next order",
                storeName: "Sample Store",
                code: "SAVE20",
                barcodeType: WatchBarcodeType.qr.rawValue,
                dvgType: WatchDVGType.discountCode.rawValue,
                expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                isFavorite: false,
                status: WatchDVGStatus.active.rawValue
            ),
            daysRemaining: 3
        )
    }

    /// Empty entry when no DVGs are available.
    static var empty: DVGExpiryEntry {
        DVGExpiryEntry(date: Date(), nextDVG: nil, daysRemaining: nil)
    }
}

// MARK: - Timeline Provider

/// Provides timeline entries for the DVG expiry complication.
///
/// Reads from the watch's local DVG cache and finds the next expiring
/// active DVG for display.
struct DVGExpiryProvider: TimelineProvider {

    func placeholder(in context: Context) -> DVGExpiryEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DVGExpiryEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let entry = fetchEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DVGExpiryEntry>) -> Void) {
        let entry = fetchEntry()

        // Refresh every 4 hours or at midnight (whichever comes first)
        let calendar = Calendar.current
        let now = entry.date

        let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let fourHoursLater = calendar.date(byAdding: .hour, value: 4, to: now) ?? now
        let nextUpdate = min(nextMidnight, fourHoursLater)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Data Fetching

    private func fetchEntry() -> DVGExpiryEntry {
        let now = Date()

        // Read from local JSON cache
        // Note: WatchDVGStore is @MainActor, but we can read the file directly
        // for the complication timeline provider since it runs in a widget extension context.
        let dvgs = loadDVGsForComplication()

        guard let nextDVG = dvgs.first(where: { $0.expirationDate != nil }),
              let expiryDate = nextDVG.expirationDate else {
            return DVGExpiryEntry(date: now, nextDVG: nil, daysRemaining: nil)
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: now, to: expiryDate).day ?? 0

        return DVGExpiryEntry(
            date: now,
            nextDVG: nextDVG,
            daysRemaining: days
        )
    }

    /// Loads DVGs directly from the cache file for the complication.
    /// This avoids MainActor isolation issues in the widget extension context.
    private func loadDVGsForComplication() -> [WatchDVG] {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let cacheFileURL = documentsDirectory.appendingPathComponent("watch_dvgs.json")

        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let dvgs = try decoder.decode([WatchDVG].self, from: data)
            return dvgs
                .filter { $0.isActive }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.expirationDate ?? Date.distantFuture
                    let rhsDate = rhs.expirationDate ?? Date.distantFuture
                    return lhsDate < rhsDate
                }
        } catch {
            return []
        }
    }
}

// MARK: - Circular Complication View

/// `accessoryCircular` complication showing days until next expiry.
private struct CircularComplicationView: View {
    let entry: DVGExpiryEntry

    var body: some View {
        if let days = entry.daysRemaining {
            ZStack {
                AccessoryWidgetBackground()

                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)

                    Text(days == 1 ? "day" : "days")
                        .font(.system(size: 8, weight: .medium))
                        .textCase(.uppercase)
                }
                .foregroundStyle(days <= 3 ? Color.red : Color.primary)
            }
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()

                Image(systemName: "tag.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rectangular Complication View

/// `accessoryRectangular` complication showing next DVG title + days.
private struct RectangularComplicationView: View {
    let entry: DVGExpiryEntry

    var body: some View {
        if let dvg = entry.nextDVG, let days = entry.daysRemaining {
            VStack(alignment: .leading, spacing: 2) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: dvg.dvgTypeEnum.iconName)
                        .font(.caption2)

                    Text("Expiring Soon")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                }
                .foregroundStyle(.secondary)

                // Title
                Text(dvg.title)
                    .font(.headline)
                    .lineLimit(1)

                // Days remaining
                HStack(spacing: 4) {
                    Text(expiryDescription(days: days))
                        .font(.caption)
                        .foregroundStyle(days <= 3 ? Color.red : Color.secondary)

                    if !dvg.storeName.isEmpty {
                        Text("at \(dvg.storeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.caption2)

                    Text("FastyDiscount")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)

                Text("No expiring discounts")
                    .font(.headline)
                    .lineLimit(1)

                Text("All clear!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func expiryDescription(days: Int) -> String {
        switch days {
        case ..<0:    return "Expired"
        case 0:       return "Expires today"
        case 1:       return "Expires tomorrow"
        default:      return "\(days) days left"
        }
    }
}

// MARK: - Complication Entry View

/// Routes to the correct layout based on complication family.
struct DVGExpiryComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: DVGExpiryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryRectangular:
            RectangularComplicationView(entry: entry)
        default:
            CircularComplicationView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

/// DVG Expiry Complication -- shows the next expiring discount on the watch face.
struct DVGExpiryComplication: Widget {
    let kind: String = "DVGExpiryComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DVGExpiryProvider()) { entry in
            DVGExpiryComplicationView(entry: entry)
        }
        .configurationDisplayName("Next Expiry")
        .description("Shows when your next discount expires.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    DVGExpiryComplication()
} timeline: {
    DVGExpiryEntry.placeholder
    DVGExpiryEntry.empty
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DVGExpiryComplication()
} timeline: {
    DVGExpiryEntry.placeholder
    DVGExpiryEntry.empty
}
