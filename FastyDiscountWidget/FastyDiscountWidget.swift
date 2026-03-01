import WidgetKit
import SwiftUI
import SwiftData

// MARK: - DVG Widget Entry

/// Lightweight data transfer struct for widget timeline entries.
/// Avoids pulling the full `@Model` DVG into the widget rendering context.
struct DVGWidgetItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let storeName: String
    let dvgType: DVGType
    let daysRemaining: Int
    let deepLinkURL: URL

    /// The urgency color based on days remaining until expiration.
    var urgencyColor: Color {
        switch daysRemaining {
        case ..<0:
            return .red
        case 0...3:
            return .red
        case 4...7:
            return Color("Warning", bundle: .main)
        default:
            return Color("Success", bundle: .main)
        }
    }

    /// Human-readable text describing the time until expiration.
    var expiryText: String {
        switch daysRemaining {
        case ..<0:
            return "Expired"
        case 0:
            return "Today"
        case 1:
            return "1 day left"
        default:
            return "\(daysRemaining) days left"
        }
    }
}

// MARK: - Timeline Entry

/// A single point-in-time snapshot of widget data.
struct ExpiringDVGEntry: TimelineEntry {
    let date: Date
    let items: [DVGWidgetItem]

    /// Whether there are any expiring DVGs to display.
    var isEmpty: Bool { items.isEmpty }

    /// Placeholder entry for the widget gallery.
    static var placeholder: ExpiringDVGEntry {
        ExpiringDVGEntry(
            date: Date(),
            items: [
                DVGWidgetItem(
                    id: UUID(),
                    title: "20% off next order",
                    storeName: "Sample Store",
                    dvgType: .discountCode,
                    daysRemaining: 3,
                    deepLinkURL: URL(string: "fastydiscount://dvg/placeholder")!
                ),
                DVGWidgetItem(
                    id: UUID(),
                    title: "$50 Gift Card",
                    storeName: "Another Store",
                    dvgType: .giftCard,
                    daysRemaining: 7,
                    deepLinkURL: URL(string: "fastydiscount://dvg/placeholder")!
                ),
                DVGWidgetItem(
                    id: UUID(),
                    title: "Loyalty Rewards",
                    storeName: "My Shop",
                    dvgType: .loyaltyPoints,
                    daysRemaining: 14,
                    deepLinkURL: URL(string: "fastydiscount://dvg/placeholder")!
                ),
            ]
        )
    }
}

// MARK: - Timeline Provider

/// Queries the shared SwiftData container for active DVGs sorted by expiration
/// date and produces timeline entries for the widget.
struct ExpiringDVGProvider: TimelineProvider {

    func placeholder(in context: Context) -> ExpiringDVGEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ExpiringDVGEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let entry = fetchEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiringDVGEntry>) -> Void) {
        let entry = fetchEntry()

        // Refresh every 6 hours
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: entry.date)
            ?? entry.date.addingTimeInterval(6 * 3600)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Data Fetching

    /// Fetches the top 3 expiring active DVGs from the shared SwiftData container.
    private func fetchEntry() -> ExpiringDVGEntry {
        let now = Date()

        do {
            let container = try ModelContainerFactory.makeReadOnlyContainer()
            let context = ModelContext(container)

            // Query: active, not soft-deleted, has an expiration date, sorted ascending
            let activeRawValue = DVGStatus.active.rawValue
            var descriptor = FetchDescriptor<DVG>(
                predicate: #Predicate<DVG> { dvg in
                    dvg.status == activeRawValue
                    && dvg.isDeleted == false
                    && dvg.expirationDate != nil
                },
                sortBy: [SortDescriptor(\.expirationDate, order: .forward)]
            )
            descriptor.fetchLimit = 3

            let dvgs = try context.fetch(descriptor)
            let calendar = Calendar.current

            let items: [DVGWidgetItem] = dvgs.compactMap { dvg in
                guard let expirationDate = dvg.expirationDate else { return nil }

                let days = calendar.dateComponents([.day], from: now, to: expirationDate).day ?? 0

                return DVGWidgetItem(
                    id: dvg.id,
                    title: dvg.title.isEmpty ? dvg.dvgTypeEnum.displayName : dvg.title,
                    storeName: dvg.storeName.isEmpty ? "Unknown Store" : dvg.storeName,
                    dvgType: dvg.dvgTypeEnum,
                    daysRemaining: days,
                    deepLinkURL: URL(string: "\(AppConstants.DeepLink.scheme)://\(AppConstants.DeepLink.dvgPath)/\(dvg.id.uuidString)")!
                )
            }

            return ExpiringDVGEntry(date: now, items: items)
        } catch {
            // If we cannot read the store, return an empty entry
            return ExpiringDVGEntry(date: now, items: [])
        }
    }
}

// MARK: - Small Widget View

/// Displays the single most urgent expiring DVG.
private struct SmallWidgetView: View {
    let entry: ExpiringDVGEntry

    var body: some View {
        if let item = entry.items.first {
            VStack(alignment: .leading, spacing: 6) {
                // Type icon
                Image(systemName: item.dvgType.iconName)
                    .font(.title2)
                    .foregroundStyle(Color("Primary", bundle: .main))
                    .accessibilityLabel("\(item.dvgType.displayName) icon")

                Spacer()

                // Title
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary", bundle: .main))
                    .lineLimit(2)
                    .accessibilityLabel("Discount: \(item.title)")

                // Store name
                Text(item.storeName)
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary", bundle: .main))
                    .lineLimit(1)
                    .accessibilityLabel("Store: \(item.storeName)")

                // Days remaining
                Text(item.expiryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.urgencyColor)
                    .accessibilityLabel("Expires: \(item.expiryText)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.deepLinkURL)
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag.slash")
                .font(.largeTitle)
                .foregroundStyle(Color("TextSecondary", bundle: .main))
                .accessibilityHidden(true)

            Text("No expiring discounts")
                .font(.caption)
                .foregroundStyle(Color("TextSecondary", bundle: .main))
                .multilineTextAlignment(.center)
                .accessibilityLabel("No expiring discounts to display")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget View

/// Displays the top 3 expiring DVGs in a compact list.
private struct MediumWidgetView: View {
    let entry: ExpiringDVGEntry

    var body: some View {
        if entry.isEmpty {
            emptyStateView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Expiring Soon")
                        .font(.headline)
                        .foregroundStyle(Color("TextPrimary", bundle: .main))
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Color("Primary", bundle: .main))
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 6)

                // DVG rows
                ForEach(Array(entry.items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 2)
                    }

                    Link(destination: item.deepLinkURL) {
                        dvgRow(item)
                    }
                }

                if entry.items.count < 3 {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dvgRow(_ item: DVGWidgetItem) -> some View {
        HStack(spacing: 8) {
            // Type icon in circle
            Image(systemName: item.dvgType.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color("Primary", bundle: .main))
                .clipShape(Circle())
                .accessibilityLabel("\(item.dvgType.displayName) icon")

            // Title and store
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color("TextPrimary", bundle: .main))
                    .lineLimit(1)
                    .accessibilityLabel("Discount: \(item.title)")

                Text(item.storeName)
                    .font(.caption2)
                    .foregroundStyle(Color("TextSecondary", bundle: .main))
                    .lineLimit(1)
                    .accessibilityLabel("Store: \(item.storeName)")
            }

            Spacer(minLength: 4)

            // Days remaining badge
            Text(item.expiryText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.urgencyColor)
                .accessibilityLabel("Expires: \(item.expiryText)")
        }
    }

    private var emptyStateView: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.title)
                .foregroundStyle(Color("TextSecondary", bundle: .main))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("No expiring discounts")
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary", bundle: .main))
                    .accessibilityLabel("No expiring discounts to display")

                Text("Your active discounts will appear here")
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary", bundle: .main))
                    .accessibilityLabel("Your active discounts will appear here")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Entry View

/// Routes to the correct layout based on widget family.
struct ExpiringDVGWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ExpiringDVGEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("Background", bundle: .main)
                }
        case .systemMedium:
            MediumWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("Background", bundle: .main)
                }
        default:
            MediumWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("Background", bundle: .main)
                }
        }
    }
}

// MARK: - Widget Configuration

/// Expiring DVG Widget -- shows the most urgent expiring discounts/vouchers/gift-cards.
struct ExpiringDVGWidget: Widget {
    let kind: String = "ExpiringDVGWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringDVGProvider()) { entry in
            ExpiringDVGWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Expiring Discounts")
        .description("See your discounts that are expiring soon.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Legacy Default Widget (kept for backward compatibility)

struct FastyDiscountProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastyDiscountEntry {
        FastyDiscountEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FastyDiscountEntry) -> Void) {
        let entry = FastyDiscountEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastyDiscountEntry>) -> Void) {
        let entry = FastyDiscountEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct FastyDiscountEntry: TimelineEntry {
    let date: Date
}

struct FastyDiscountWidgetEntryView: View {
    var entry: FastyDiscountProvider.Entry

    var body: some View {
        VStack {
            Text("FastyDiscount")
                .font(.headline)
            Text(entry.date, style: .time)
                .font(.caption)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct FastyDiscountWidget: Widget {
    let kind: String = "FastyDiscountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastyDiscountProvider()) { entry in
            FastyDiscountWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("FastyDiscount")
        .description("View your latest discounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
