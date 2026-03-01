import WidgetKit
import SwiftUI

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
