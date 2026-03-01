import SwiftUI
import CloudKit

// MARK: - SettingsView

/// The Settings tab root view. Organizes all configuration options into
/// a native SwiftUI Form with labeled Section groups.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(AppearanceManager.self) private var appearanceManager
    @Environment(LocationPermissionManager.self) private var locationPermissionManager

    var body: some View {
        Form {
            accountSection
            emailSection
            notificationsSection
            locationSection
            aiSection
            appearanceSection
            aboutSection
            removeAdsSection
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.onAppear()
        }
        .alert("Gmail Error", isPresented: Binding(
            get: { viewModel.gmailErrorMessage != nil },
            set: { if !$0 { viewModel.gmailErrorMessage = nil } }
        )) {
            Button("OK") { viewModel.gmailErrorMessage = nil }
        } message: {
            Text(viewModel.gmailErrorMessage ?? "")
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            // Sign In with Apple status
            HStack {
                Label("Apple ID", systemImage: "applelogo")
                Spacer()
                Text(viewModel.isSignedIn ? "Signed In" : "Not Signed In")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(viewModel.isSignedIn
                        ? Theme.Colors.success
                        : Theme.Colors.textSecondary)
            }

            // CloudKit sync status
            HStack {
                Label("iCloud Sync", systemImage: viewModel.cloudKitStatus.systemImage)
                Spacer()
                Text(viewModel.cloudKitStatus.label)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(cloudKitStatusColor)
            }

            // Sign out button
            if viewModel.isSignedIn {
                Button(role: .destructive) {
                    Task {
                        await viewModel.signOut {
                            // Sign-out is handled by AuthViewModel at the app level.
                            // This button signals intent; the AuthViewModel drives the state.
                        }
                    }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } header: {
            Text("Account")
        }
    }

    private var cloudKitStatusColor: Color {
        switch viewModel.cloudKitStatus {
        case .available:
            return Theme.Colors.success
        case .error:
            return Theme.Colors.error
        case .syncing, .unknown:
            return Theme.Colors.textSecondary
        }
    }

    // MARK: - Email Section

    @ViewBuilder
    private var emailSection: some View {
        Section {
            // Gmail connection status
            HStack {
                Label("Gmail", systemImage: "envelope")
                Spacer()
                if viewModel.isGmailOperationInProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(viewModel.isGmailConnected ? "Connected" : "Not Connected")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(viewModel.isGmailConnected
                            ? Theme.Colors.success
                            : Theme.Colors.textSecondary)
                }
            }

            // Connect / Disconnect button
            if viewModel.isGmailConnected {
                Button(role: .destructive) {
                    Task { await viewModel.disconnectGmail() }
                } label: {
                    Label("Disconnect Gmail", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isGmailOperationInProgress)
            } else {
                Button {
                    Task { await viewModel.connectGmail() }
                } label: {
                    Label("Connect Gmail", systemImage: "envelope.badge.shield.half.filled")
                }
                .disabled(viewModel.isGmailOperationInProgress)
            }

            // Scan scope link — navigates to email scan settings
            NavigationLink {
                EmailScanView()
            } label: {
                Label("Scan Scope Settings", systemImage: "scope")
            }
        } header: {
            Text("Email")
        } footer: {
            Text("Connect your Gmail account to automatically scan for discount vouchers.")
        }
    }

    // MARK: - Notifications Section

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            // System status banner if denied
            if viewModel.notificationSystemStatus == .denied {
                HStack {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(Theme.Colors.warning)
                    Text("Notifications are disabled in Settings.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Enable", destination: settingsURL)
                            .font(Theme.Typography.footnote)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            // Global notifications toggle
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.notificationsEnabled = $0 }
            )) {
                Label("Notifications", systemImage: "bell")
            }
            .disabled(viewModel.notificationSystemStatus == .denied)

            // Expiry notifications toggle
            Toggle(isOn: Binding(
                get: { viewModel.expiryNotificationsEnabled },
                set: { viewModel.expiryNotificationsEnabled = $0 }
            )) {
                Label("Expiry Reminders", systemImage: "calendar.badge.exclamationmark")
            }
            .disabled(!viewModel.notificationsEnabled
                      || viewModel.notificationSystemStatus == .denied)

            // Location notifications toggle
            Toggle(isOn: Binding(
                get: { viewModel.locationNotificationsEnabled },
                set: { viewModel.locationNotificationsEnabled = $0 }
            )) {
                Label("Nearby Store Alerts", systemImage: "location.circle")
            }
            .disabled(!viewModel.notificationsEnabled
                      || viewModel.notificationSystemStatus == .denied)
        } header: {
            Text("Notifications")
        } footer: {
            if viewModel.notificationSystemStatus == .denied {
                Text("Enable notifications in iOS Settings to receive expiry and location alerts.")
            } else {
                Text("Control when FastyDiscount reminds you about your discounts.")
            }
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
        Section {
            // Permission status
            HStack {
                Label("Permission", systemImage: "location")
                Spacer()
                Text(locationPermissionStatusLabel)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(locationPermissionStatusColor)
            }

            // Open Settings link if denied / restricted
            if locationPermissionManager.authorizationState == .denied
                || locationPermissionManager.authorizationState == .restricted {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsURL) {
                        Label("Open Location Settings", systemImage: "gear")
                    }
                }
            }

            // Geofencing enable/disable
            Toggle(isOn: Binding(
                get: { viewModel.geofencingEnabled },
                set: { viewModel.geofencingEnabled = $0 }
            )) {
                Label("Geofencing", systemImage: "mappin.and.ellipse")
            }

            // Default radius slider (100m – 1000m)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Label("Default Radius", systemImage: "circle.dashed")
                    Spacer()
                    Text("\(Int(viewModel.defaultGeofenceRadius))m")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { viewModel.defaultGeofenceRadius },
                        set: { viewModel.defaultGeofenceRadius = $0 }
                    ),
                    in: 100...1000,
                    step: 50
                ) {
                    Text("Radius")
                } minimumValueLabel: {
                    Text("100m")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } maximumValueLabel: {
                    Text("1km")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .disabled(!viewModel.geofencingEnabled)
            }
        } header: {
            Text("Location")
        } footer: {
            Text("Geofencing lets FastyDiscount alert you when you're near a store where you have an active discount.")
        }
    }

    private var locationPermissionStatusLabel: String {
        switch locationPermissionManager.authorizationState {
        case .notDetermined: return "Not Determined"
        case .restricted:    return "Restricted"
        case .denied:        return "Denied"
        case .whenInUse:     return "When In Use"
        case .always:        return "Always"
        }
    }

    private var locationPermissionStatusColor: Color {
        switch locationPermissionManager.authorizationState {
        case .denied, .restricted: return Theme.Colors.error
        case .whenInUse, .always:  return Theme.Colors.success
        case .notDetermined:       return Theme.Colors.textSecondary
        }
    }

    // MARK: - AI Section (Anthropic only)

    @ViewBuilder
    private var aiSection: some View {
        Section {
            // Provider — Anthropic only (no picker; this app only uses Anthropic)
            HStack {
                Label("Provider", systemImage: "cpu")
                Spacer()
                Text("Anthropic")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            // API Key entry with reveal toggle
            HStack {
                Label("API Key", systemImage: "key")

                if viewModel.isAPIKeyRevealed {
                    TextField(
                        "Enter Anthropic API key",
                        text: Binding(
                            get: { viewModel.anthropicAPIKey },
                            set: { viewModel.anthropicAPIKey = $0 }
                        )
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                } else {
                    SecureField(
                        "Enter Anthropic API key",
                        text: Binding(
                            get: { viewModel.anthropicAPIKey },
                            set: { viewModel.anthropicAPIKey = $0 }
                        )
                    )
                    .multilineTextAlignment(.trailing)
                }

                Button {
                    viewModel.isAPIKeyRevealed.toggle()
                } label: {
                    Image(systemName: viewModel.isAPIKeyRevealed
                          ? "eye.slash"
                          : "eye")
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isAPIKeyRevealed
                                    ? "Hide API key"
                                    : "Reveal API key")
            }

            // Usage stats
            HStack {
                Label("Total Parses", systemImage: "chart.bar")
                Spacer()
                Text("\(viewModel.parseCount)")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
        } header: {
            Text("AI")
        } footer: {
            Text("FastyDiscount uses Anthropic Claude to extract discount details from scanned content. Your API key is stored locally on this device.\n\nNote: In production this key should be stored in the Keychain.")
        }
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var appearanceManager = appearanceManager

        Section {
            Picker(selection: $appearanceManager.preference) {
                ForEach(AppearancePreference.allCases, id: \.self) { preference in
                    Text(preference.label).tag(preference)
                }
            } label: {
                Label("Color Scheme", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            // App version
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            // Privacy policy
            Link(destination: URL(string: "https://fastydiscount.app/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            // Open source licenses
            Link(destination: URL(string: "https://fastydiscount.app/licenses")!) {
                Label("Open Source Licenses", systemImage: "doc.text")
            }

            // Contact / feedback
            Link(destination: URL(string: "https://fastydiscount.app/feedback")!) {
                Label("Contact & Feedback", systemImage: "envelope")
            }
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - Remove Ads Section

    @ViewBuilder
    private var removeAdsSection: some View {
        Section {
            // Remove Ads IAP button (placeholder — implemented in TASK-041)
            Button {
                // TODO: TASK-041 — implement Remove Ads IAP purchase flow
            } label: {
                HStack {
                    Label("Remove Ads", systemImage: "sparkles")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .foregroundStyle(Theme.Colors.primary)

            // Restore Purchases button (placeholder — implemented in TASK-041)
            Button {
                // TODO: TASK-041 — implement Restore Purchases flow
            } label: {
                Label("Restore Purchases", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(Theme.Colors.primary)
        } header: {
            Text("Purchases")
        } footer: {
            Text("Remove Ads is a one-time purchase. Restore Purchases recovers any previous purchases on this Apple ID.")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppearanceManager())
            .environment(LocationPermissionManager())
    }
}
