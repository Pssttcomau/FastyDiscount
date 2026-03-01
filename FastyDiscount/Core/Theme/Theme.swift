import SwiftUI

// MARK: - Theme

/// Central namespace for all design tokens used across the app.
/// Colors reference asset catalog entries so they automatically adapt
/// to light / dark mode without any additional code.
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// Teal primary brand color. Light: #0D9488 / Dark: #2DD4BF
        static let primary = Color("Primary", bundle: .main)

        /// Slate secondary color. Light: #475569 / Dark: #94A3B8
        static let secondary = Color("Secondary", bundle: .main)

        /// Coral accent color. Light: #F97316 / Dark: #FB923C
        static let accent = Color("Accent", bundle: .main)

        /// Page background. Light: #FFFFFF / Dark: #0F172A
        static let background = Color("Background", bundle: .main)

        /// Card / elevated surface. Light: #F8FAFC / Dark: #1E293B
        static let surface = Color("Surface", bundle: .main)

        /// High-contrast body text. Light: #0F172A / Dark: #F8FAFC
        static let textPrimary = Color("TextPrimary", bundle: .main)

        /// Subdued secondary text. Light: #64748B / Dark: #94A3B8
        static let textSecondary = Color("TextSecondary", bundle: .main)

        /// Dividers and input borders. Light: #E2E8F0 / Dark: #334155
        static let border = Color("Border", bundle: .main)

        /// Error / destructive state. Light: #DC2626 / Dark: #EF4444
        static let error = Color("Error", bundle: .main)

        /// Success / confirmation state. Light: #16A34A / Dark: #22C55E
        static let success = Color("Success", bundle: .main)

        /// Warning / caution state. Light: #D97706 / Dark: #F59E0B
        static let warning = Color("Warning", bundle: .main)
    }

    // MARK: - Typography

    /// All font styles use `Font.TextStyle` so Dynamic Type scaling is automatic.
    /// Custom font support can be layered on top via `.fontDesign()` or a
    /// custom font family registered in Info.plist.
    enum Typography {
        static let largeTitle  = Font.largeTitle
        static let title       = Font.title
        static let title2      = Font.title2
        static let title3      = Font.title3
        static let headline    = Font.headline
        static let body        = Font.body
        static let callout     = Font.callout
        static let subheadline = Font.subheadline
        static let footnote    = Font.footnote
        static let caption     = Font.caption
        static let caption2    = Font.caption2
    }

    // MARK: - Spacing

    /// Consistent spacing scale in points.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small:  CGFloat = 8
        static let medium: CGFloat = 12
        static let large:  CGFloat = 16
    }
}

// MARK: - Convenience accessors at Theme level

extension Theme {
    /// Shorthand: `Theme.primary` instead of `Theme.Colors.primary`.
    static var primary:       Color { Colors.primary }
    static var secondary:     Color { Colors.secondary }
    static var accent:        Color { Colors.accent }
    static var background:    Color { Colors.background }
    static var surface:       Color { Colors.surface }
    static var textPrimary:   Color { Colors.textPrimary }
    static var textSecondary: Color { Colors.textSecondary }
    static var border:        Color { Colors.border }
    static var error:         Color { Colors.error }
    static var success:       Color { Colors.success }
    static var warning:       Color { Colors.warning }
}
