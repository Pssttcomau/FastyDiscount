import SwiftUI

// MARK: - CardModifier

/// A `ViewModifier` that applies consistent card styling:
/// surface background, rounded corners, and a subtle shadow.
///
/// Usage:
/// ```swift
/// VStack { ... }
///     .cardStyle()
/// ```
struct CardModifier: ViewModifier {

    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(0.08),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
}

// MARK: - View Extension

extension View {

    /// Applies standard card styling with a medium corner radius and subtle shadow.
    func cardStyle(
        cornerRadius: CGFloat = Theme.CornerRadius.medium,
        shadowRadius: CGFloat = 6,
        shadowY: CGFloat = 2
    ) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowY: shadowY))
    }
}
