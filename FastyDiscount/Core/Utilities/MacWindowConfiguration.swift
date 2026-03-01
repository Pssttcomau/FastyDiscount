import SwiftUI

#if targetEnvironment(macCatalyst)
import UIKit

// MARK: - MacWindowConfiguration

/// Applies Mac Catalyst-specific window configuration.
///
/// Sets the minimum window size (800 × 600) so the app layout does not
/// collapse below a usable threshold on macOS. The default window size is
/// controlled by `WindowGroup.defaultSize(width:height:)` in `FastyDiscountApp`.
///
/// Usage: attach `.onAppear { MacWindowConfiguration.apply(to: window) }`
/// to the root scene, or call from a `UIWindowScene` delegate callback.
enum MacWindowConfiguration {

    /// Minimum window width in points (matches HIG recommendation for utility-style windows).
    static let minimumWidth: CGFloat = 800

    /// Minimum window height in points.
    static let minimumHeight: CGFloat = 600

    /// Applies minimum size constraints to the Mac Catalyst window.
    ///
    /// Call this once from a `WindowGroup` view using a `.background(WindowAccessor())` approach
    /// or from the scene delegate.
    static func apply(to scene: UIWindowScene) {
        // UIWindowScene.sizeRestrictions is available on Mac Catalyst
        if let restrictions = scene.sizeRestrictions {
            restrictions.minimumSize = CGSize(width: minimumWidth, height: minimumHeight)
            // Set a reasonable maximum to avoid an overly stretched layout;
            // nil means no maximum (fully resizable).
            restrictions.maximumSize = .zero // .zero means "no restriction" on Mac Catalyst
        }
    }
}

// MARK: - MacWindowSizeModifier

/// A view modifier that applies Mac window size restrictions once the
/// window scene becomes available.
///
/// Attach this to the root `ContentView` inside `WindowGroup` when targeting
/// Mac Catalyst. On non-Mac platforms, this is a no-op.
struct MacWindowSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MacWindowSceneAccessor())
    }
}

// MARK: - MacWindowSceneAccessor

/// A zero-size UIViewRepresentable that extracts the hosting UIWindowScene
/// and applies window size restrictions via `MacWindowConfiguration`.
private struct MacWindowSceneAccessor: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Walk the responder chain to find the UIWindowScene once the view is in the hierarchy
        DispatchQueue.main.async {
            if let scene = uiView.window?.windowScene {
                MacWindowConfiguration.apply(to: scene)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies Mac Catalyst window size constraints (minimum 800 × 600).
    /// No-op on iOS and iPadOS.
    func macWindowSizeConstraints() -> some View {
        modifier(MacWindowSizeModifier())
    }
}

#else

// MARK: - Non-Mac stub

extension View {
    /// No-op on non-Mac platforms.
    func macWindowSizeConstraints() -> some View {
        self
    }
}

#endif
