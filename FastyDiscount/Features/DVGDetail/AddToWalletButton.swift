import PassKit
import SwiftUI

// MARK: - AddToWalletButton

/// A SwiftUI wrapper around `PKAddPassButton` that presents the native
/// "Add to Apple Wallet" button styling.
///
/// Uses `UIViewRepresentable` to bridge the UIKit `PKAddPassButton` into SwiftUI.
/// The button automatically adopts Apple's official wallet button design,
/// adapting to the current interface style (light/dark).
///
/// Only renders when `PKAddPassesViewController.canAddPasses()` returns `true`.
struct AddToWalletButton: UIViewRepresentable {

    /// Called when the user taps the button.
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.buttonTapped),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        // No dynamic updates needed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonTapped() {
            action()
        }
    }
}

// MARK: - WalletSection

/// A reusable section view that shows the "Add to Apple Wallet" button
/// or "Already in Wallet" status for a DVG item.
///
/// Handles three states:
/// 1. **Eligible, not added**: Shows the native `PKAddPassButton`.
/// 2. **Already added**: Shows a confirmation label with a checkmark.
/// 3. **Not eligible / not supported**: Not rendered (empty view).
struct WalletSection: View {

    /// Whether the device supports adding passes.
    let canAddPasses: Bool

    /// Whether the DVG is eligible for a wallet pass (has barcode data).
    let isEligible: Bool

    /// Whether a pass for this DVG is already in the user's wallet.
    let isAlreadyAdded: Bool

    /// Whether a wallet operation is currently in progress.
    let isProcessing: Bool

    /// Called when the user taps "Add to Apple Wallet".
    let onAddToWallet: () -> Void

    /// Called when the user taps "Remove from Wallet".
    let onRemoveFromWallet: () -> Void

    var body: some View {
        if canAddPasses && isEligible {
            VStack(spacing: Theme.Spacing.sm) {
                if isAlreadyAdded {
                    // Pass is already in wallet
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.success)
                            .font(Theme.Typography.body)

                        Text("Added to Apple Wallet")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.success)

                        Spacer()

                        Button {
                            onRemoveFromWallet()
                        } label: {
                            Text("Remove")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.error)
                        }
                        .disabled(isProcessing)
                    }
                    .padding(Theme.Spacing.md)
                    .cardStyle()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pass added to Apple Wallet")
                    .accessibilityHint("Tap Remove to remove the pass from your wallet")
                } else {
                    // Show Add to Wallet button
                    if isProcessing {
                        ProgressView("Adding to Wallet...")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .cardStyle()
                    } else {
                        AddToWalletButton {
                            onAddToWallet()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .accessibilityLabel("Add to Apple Wallet")
                        .accessibilityHint("Adds this discount as a pass in your Apple Wallet")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Wallet Section - Not Added") {
    VStack {
        WalletSection(
            canAddPasses: true,
            isEligible: true,
            isAlreadyAdded: false,
            isProcessing: false,
            onAddToWallet: { },
            onRemoveFromWallet: { }
        )
    }
    .padding()
}

#Preview("Wallet Section - Added") {
    VStack {
        WalletSection(
            canAddPasses: true,
            isEligible: true,
            isAlreadyAdded: true,
            isProcessing: false,
            onAddToWallet: { },
            onRemoveFromWallet: { }
        )
    }
    .padding()
}
#endif
