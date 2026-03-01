import SwiftUI
import WatchKit

// MARK: - DVGBarcodeView

/// Full-screen barcode/QR code display for scanning at point-of-sale.
///
/// Features:
/// - Renders the barcode at maximum size for the watch display
/// - Auto-increases screen brightness for scanner readability
/// - Shows the code text below for manual entry fallback
/// - Provides a "Mark as Used" button that sends action to iPhone
struct DVGBarcodeView: View {

    let dvg: WatchDVG

    @Environment(\.dismiss) private var dismiss
    @State private var isMarkedAsUsed = false
    @State private var showingConfirmation = false
    @State private var extendedSession: WKExtendedRuntimeSession?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Barcode image
                barcodeContent
                    .accessibilityLabel("Barcode for \(dvg.title)")

                // Code text for manual entry
                if !dvg.code.isEmpty {
                    codeText
                }

                // Mark as Used button
                markAsUsedButton
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(dvg.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            increaseBrightness()
        }
        .onDisappear {
            restoreBrightness()
        }
        .confirmationDialog(
            "Mark as Used?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Used", role: .destructive) {
                markAsUsed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark \"\(dvg.title)\" as used.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var barcodeContent: some View {
        let barcodeType = dvg.barcodeTypeEnum

        if WatchBarcodeGenerator.canRender(type: barcodeType) {
            WatchBarcodeGenerator.barcodeView(
                from: dvg.barcodeValue,
                type: barcodeType
            )
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            // Fallback for text-only or unsupported barcode types
            VStack(spacing: 8) {
                Image(systemName: dvg.dvgTypeEnum.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("No barcode available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var codeText: some View {
        VStack(spacing: 2) {
            Text("Code")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(dvg.code)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code: \(dvg.code)")
    }

    private var markAsUsedButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack {
                Image(systemName: isMarkedAsUsed ? "checkmark.circle.fill" : "checkmark.circle")
                Text(isMarkedAsUsed ? "Marked as Used" : "Mark as Used")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isMarkedAsUsed ? .secondary : .blue)
        .disabled(isMarkedAsUsed)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func markAsUsed() {
        // Update local cache
        WatchDVGStore.shared.updateStatus(for: dvg.id, to: .used)

        // Send action to iPhone via Watch Connectivity
        WatchConnectivityManager.shared.sendMarkAsUsed(dvgID: dvg.id)

        withAnimation {
            isMarkedAsUsed = true
        }

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: - Brightness Management

    /// Keeps the display active and prevents dimming while the barcode is shown.
    ///
    /// watchOS has no public API equivalent to iOS's `UIScreen.main.brightness`.
    /// Instead, we start a `WKExtendedRuntimeSession` which keeps the display
    /// active and prevents the screen from dimming or sleeping, ensuring the
    /// barcode remains visible for scanning.
    ///
    /// NOTE: This may require the `com.apple.developer.watchkit.background-mode`
    /// entitlement with the `self-care` or `smart-alarm` session type configured
    /// in the app's entitlements file.
    private func increaseBrightness() {
        // Play a subtle haptic to indicate the barcode is ready for scanning
        WKInterfaceDevice.current().play(.click)

        // Start an extended runtime session to keep the display active
        let session = WKExtendedRuntimeSession()
        session.start()
        extendedSession = session
    }

    /// Ends the extended runtime session when leaving the barcode view,
    /// allowing watchOS to resume normal display dimming behavior.
    private func restoreBrightness() {
        extendedSession?.invalidate()
        extendedSession = nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DVGBarcodeView(dvg: WatchDVG.previews[0])
    }
}
