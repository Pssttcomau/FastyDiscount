import Foundation

// MARK: - LocaleFormatters

/// Provides locale-aware formatters for dates, currencies, and numbers.
///
/// All formatters automatically respect the user's current locale and region
/// settings. Do not use hardcoded format strings or fallback to `$` symbols.
///
/// Usage examples:
/// ```swift
/// // Date — abbreviated (e.g. "Jan 15, 2026")
/// let dateString = LocaleFormatters.abbreviatedDate.string(from: someDate)
///
/// // Date with time (e.g. "Jan 15, 2026 at 2:30 PM")
/// let dateTimeString = LocaleFormatters.mediumDateShortTime.string(from: someDate)
///
/// // Currency (e.g. "$12.50" in en_US, "£12.50" in en_GB)
/// let priceString = LocaleFormatters.currency(for: 12.50)
///
/// // Integer (e.g. "1,250" in en_US, "1.250" in de_DE)
/// let countString = LocaleFormatters.integer(for: 1250)
/// ```
enum LocaleFormatters {

    // MARK: - Date Formatters

    /// Formatter for medium-style dates without time component.
    /// Example output: "Jan 15, 2026" (en_US), "15. Jan. 2026" (de_DE)
    static let abbreviatedDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = .autoupdatingCurrent
        return f
    }()

    /// Formatter for medium-style date with short time component.
    /// Example output: "Jan 15, 2026 at 2:30 PM" (en_US)
    static let mediumDateShortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = .autoupdatingCurrent
        return f
    }()

    // MARK: - Currency Formatter

    /// Returns a locale-aware currency string for a given Double value.
    ///
    /// Uses the user's current locale to determine the currency symbol and
    /// formatting conventions. Falls back to a plain two-decimal string if
    /// formatting fails.
    ///
    /// - Parameter value: The monetary value to format.
    /// - Returns: A locale-formatted currency string (e.g. "$12.50", "€12,50").
    static func currency(for value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Returns a locale-aware currency string for a given Decimal value.
    ///
    /// - Parameter value: The Decimal monetary value to format.
    /// - Returns: A locale-formatted currency string.
    static func currency(for value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    // MARK: - Number Formatters

    /// Returns a locale-aware decimal string for a given integer.
    ///
    /// Example output: "1,250" (en_US), "1.250" (de_DE)
    ///
    /// - Parameter value: The integer value to format.
    /// - Returns: A locale-formatted integer string.
    static func integer(for value: Int) -> String {
        value.formatted(.number.locale(.autoupdatingCurrent))
    }

    /// Returns a locale-aware decimal string for a given Double.
    ///
    /// Example output: "12.5" (en_US), "12,5" (de_DE)
    ///
    /// - Parameter value: The floating-point value to format.
    /// - Parameter fractionDigits: Number of decimal places (default 2).
    /// - Returns: A locale-formatted decimal string.
    static func decimal(for value: Double, fractionDigits: Int = 2) -> String {
        value.formatted(
            .number
            .precision(.fractionLength(fractionDigits))
            .locale(.autoupdatingCurrent)
        )
    }

    // MARK: - Date FormatStyle helpers

    /// Returns a locale-aware abbreviated date string using Swift's FormatStyle API.
    /// Preferred API for SwiftUI `Text` interpolation.
    ///
    /// Example: `Text(someDate.formatted(date: .abbreviated, time: .omitted))`
    static func abbreviated(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Returns a locale-aware date + time string using Swift's FormatStyle API.
    static func abbreviatedWithTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
