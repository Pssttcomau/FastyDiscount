import SwiftData
import SwiftUI

// MARK: - EmailScanView

/// The main Email Scan feature view.
///
/// Allows the user to connect a Gmail account, configure scan scope settings,
/// trigger an AI-powered inbox scan, and view progress and results in real time.
///
/// Presents a sheet for scope settings and runs the scan pipeline without
/// blocking the rest of the app navigation stack.
struct EmailScanView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router

    // MARK: - State

    @State private var viewModel: EmailScanViewModel?

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                mainContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Email Scan")
        .navigationBarTitleDisplayMode(.large)
        .task {
            setupViewModel()
        }
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard viewModel == nil else { return }

        let authService = GoogleGmailAuthService()
        let apiClient = GoogleGmailAPIClient(authService: authService)
        let parsingService = CloudAIEmailParsingService(
            aiClient: AnthropicClient(),
            modelContext: modelContext
        )

        viewModel = EmailScanViewModel(
            authService: authService,
            apiClient: apiClient,
            parsingService: parsingService
        )
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(viewModel: EmailScanViewModel) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                gmailConnectionSection(viewModel: viewModel)
                scanScopeSection(viewModel: viewModel)
                scanControlSection(viewModel: viewModel)

                // Progress is shown inline when scanning
                switch viewModel.scanState {
                case .fetchingEmails:
                    fetchingProgressView()
                case .parsing(let current, let total):
                    parsingProgressView(viewModel: viewModel, current: current, total: total)
                case .complete:
                    if let summary = viewModel.scanSummary {
                        scanResultsSummaryView(viewModel: viewModel, summary: summary)
                    }
                case .failed(let message):
                    errorStateView(message: message, viewModel: viewModel)
                case .idle:
                    EmptyView()
                }

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: Bindable(viewModel).showScopeSettings) {
            ScopeSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Full Inbox Scan", isPresented: Bindable(viewModel).showFullInboxWarning) {
            Button("Scan Full Inbox", role: .destructive) {
                viewModel.confirmFullInboxScan()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Scanning your full inbox may take longer and will process all emails, not just promotions. This may use more AI API quota.")
        }
        .alert("Error", isPresented: Bindable(viewModel).showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Gmail Connection Section

    @ViewBuilder
    private func gmailConnectionSection(viewModel: EmailScanViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Gmail Account")

            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(viewModel.isGmailConnected
                              ? Theme.Colors.success.opacity(0.15)
                              : Theme.Colors.border.opacity(0.5))
                        .frame(width: 44, height: 44)

                    Image(systemName: viewModel.isGmailConnected ? "checkmark.circle.fill" : "envelope.badge.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(viewModel.isGmailConnected ? Theme.Colors.success : Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(viewModel.isGmailConnected ? "Gmail Connected" : "Gmail Not Connected")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(viewModel.isGmailConnected
                         ? "Your Gmail account is ready to scan."
                         : "Connect your Gmail account to scan for discounts.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isGmailConnected {
                    Button(role: .destructive) {
                        Task { await viewModel.disconnectGmail() }
                    } label: {
                        if viewModel.isConnecting {
                            ProgressView()
                                .tint(Theme.Colors.error)
                        } else {
                            Text("Disconnect")
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(color: Theme.Colors.error))
                    .disabled(viewModel.isConnecting)
                    .accessibilityLabel("Disconnect Gmail account")
                } else {
                    Button {
                        Task { await viewModel.connectGmail() }
                    } label: {
                        if viewModel.isConnecting {
                            HStack(spacing: Theme.Spacing.xs) {
                                ProgressView()
                                    .tint(.white)
                                Text("Connecting...")
                            }
                        } else {
                            Label("Connect Gmail", systemImage: "envelope.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isConnecting)
                    .accessibilityLabel("Connect Gmail account")
                    .accessibilityHint("Opens Google sign-in to connect your Gmail")
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Scan Scope Section

    @ViewBuilder
    private func scanScopeSection(viewModel: EmailScanViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                sectionHeader("Scan Scope")
                Spacer()
                Button {
                    viewModel.showScopeSettings = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.primary)
                }
                .accessibilityLabel("Edit scan scope settings")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                scopeRow(
                    icon: "tag.fill",
                    title: "Labels",
                    value: viewModel.scanFullInbox
                        ? "Full Inbox"
                        : (viewModel.selectedLabels.isEmpty
                           ? "Promotions"
                           : viewModel.selectedLabels.joined(separator: ", "))
                )

                Divider()
                    .background(Theme.Colors.border)

                scopeRow(
                    icon: "person.fill",
                    title: "Senders",
                    value: viewModel.senderWhitelist.isEmpty
                        ? "All senders"
                        : "\(viewModel.senderWhitelist.count) whitelisted"
                )

                if let sinceDate = viewModel.sinceDate {
                    Divider()
                        .background(Theme.Colors.border)

                    scopeRow(
                        icon: "calendar",
                        title: "Since",
                        value: sinceDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func scopeRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 20)

            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(Theme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Scan Control Section

    @ViewBuilder
    private func scanControlSection(viewModel: EmailScanViewModel) -> some View {
        let isScanning: Bool = {
            switch viewModel.scanState {
            case .fetchingEmails, .parsing: return true
            default: return false
            }
        }()

        VStack(spacing: Theme.Spacing.sm) {
            if isScanning {
                Button(role: .destructive) {
                    viewModel.cancelScan()
                } label: {
                    Label("Cancel Scan", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle(color: Theme.Colors.error))
                .accessibilityLabel("Cancel the in-progress scan")
            } else {
                Button {
                    if !viewModel.isGmailConnected {
                        viewModel.showError = true
                        viewModel.errorMessage = "Gmail is not connected. Please connect your Gmail account first."
                        return
                    }
                    viewModel.startScan()
                } label: {
                    Label("Scan Inbox", systemImage: "envelope.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Start scanning inbox for discounts")
                .accessibilityHint("Fetches emails and uses AI to find discount codes and vouchers")
            }
        }
    }

    // MARK: - Fetching Progress View

    @ViewBuilder
    private func fetchingProgressView() -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.primary)

            Text("Fetching emails from Gmail...")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .cardStyle()
    }

    // MARK: - Parsing Progress View

    @ViewBuilder
    private func parsingProgressView(
        viewModel: EmailScanViewModel,
        current: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Parsing Emails")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Text("\(current) / \(total)")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }

            ProgressView(value: viewModel.progressFraction)
                .tint(Theme.Colors.primary)
                .accessibilityLabel("Scan progress \(Int(viewModel.progressFraction * 100)) percent")

            // Per-email status list
            if !viewModel.emailStatuses.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(viewModel.emailStatuses.indices, id: \.self) { index in
                        emailStatusRow(status: viewModel.emailStatuses[index], index: index)
                    }
                }
                .frame(maxHeight: 200)
                .clipped()
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func emailStatusRow(status: EmailItemStatus, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            statusIcon(for: status)
                .frame(width: 16)

            Text("Email \(index + 1)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            statusLabel(for: status)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: EmailItemStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(Theme.Colors.textSecondary)
                .font(.caption2)
        case .parsing:
            ProgressView()
                .scaleEffect(0.6)
                .tint(Theme.Colors.primary)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.Colors.error)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func statusLabel(for status: EmailItemStatus) -> some View {
        switch status {
        case .pending:
            Text("Pending")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .parsing:
            Text("Parsing...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.primary)
        case .done:
            Text("Done")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.success)
        case .failed(let msg):
            Text("Failed")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.error)
                .help(msg)
        }
    }

    // MARK: - Scan Results Summary

    @ViewBuilder
    private func scanResultsSummaryView(
        viewModel: EmailScanViewModel,
        summary: EmailScanSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .font(.title2)

                Text("Scan Complete")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack(spacing: 0) {
                summaryStatView(
                    value: "\(summary.totalDVGsFound)",
                    label: "DVGs Found",
                    color: Theme.Colors.primary
                )

                Divider()
                    .frame(height: 40)

                summaryStatView(
                    value: "\(summary.autoSaved)",
                    label: "Auto-Saved",
                    color: Theme.Colors.success
                )

                Divider()
                    .frame(height: 40)

                summaryStatView(
                    value: "\(summary.needReview)",
                    label: "Need Review",
                    color: summary.needReview > 0 ? Theme.Colors.warning : Theme.Colors.textSecondary
                )
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            if summary.needReview > 0 {
                Button {
                    router.push(.reviewQueue)
                } label: {
                    Label("View Review Queue", systemImage: "list.clipboard.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("View \(summary.needReview) items in the review queue")
            }

            Button {
                viewModel.cancelScan() // resets state to idle
            } label: {
                Text("Scan Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle(color: Theme.Colors.primary))
            .accessibilityLabel("Start another scan")
        }
        .cardStyle()
    }

    @ViewBuilder
    private func summaryStatView(value: String, label: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .monospacedDigit()

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error State View

    @ViewBuilder
    private func errorStateView(message: String, viewModel: EmailScanViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                    .font(.title2)

                Text("Scan Failed")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Text(message)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.cancelScan() // Reset to idle
            } label: {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle(color: Theme.Colors.primary))
            .accessibilityLabel("Dismiss error and try again")
        }
        .cardStyle()
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

// MARK: - ScopeSettingsSheet

/// A sheet for editing the email scan scope settings.
///
/// Allows the user to:
/// - Pick Gmail labels to filter by
/// - Add/remove sender whitelist entries
/// - Toggle full inbox scan (with warning)
/// - Set a "since date" filter
private struct ScopeSettingsSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: EmailScanViewModel
    @State private var showDatePicker: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                labelSection
                senderWhitelistSection
                fullInboxSection
                dateFilterSection
            }
            .navigationTitle("Scan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.saveScopeSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Save settings and close")
                }
            }
            .task {
                await viewModel.fetchAvailableLabels()
            }
        }
    }

    // MARK: - Label Section

    @ViewBuilder
    private var labelSection: some View {
        Section {
            if viewModel.isFetchingLabels {
                HStack {
                    ProgressView()
                    Text("Loading labels...")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                ForEach(viewModel.availableLabels.isEmpty
                        ? GmailLabel.defaultLabels
                        : viewModel.availableLabels) { label in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedLabels.contains(label.id) },
                        set: { isSelected in
                            if isSelected {
                                if !viewModel.selectedLabels.contains(label.id) {
                                    viewModel.selectedLabels.append(label.id)
                                }
                            } else {
                                viewModel.selectedLabels.removeAll { $0 == label.id }
                            }
                        }
                    )) {
                        Label(label.name, systemImage: "tag.fill")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .disabled(viewModel.scanFullInbox)
                    .accessibilityLabel("Label: \(label.name)")
                }
            }
        } header: {
            Text("Gmail Labels")
        } footer: {
            Text("Select which labels to scan. Ignored when Full Inbox is enabled.")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Sender Whitelist Section

    @ViewBuilder
    private var senderWhitelistSection: some View {
        Section {
            ForEach(viewModel.senderWhitelist, id: \.self) { sender in
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Theme.Colors.primary)
                    Text(sender)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .onDelete { offsets in
                viewModel.removeSenders(at: offsets)
            }

            HStack(spacing: Theme.Spacing.sm) {
                TextField("sender@example.com", text: $viewModel.newSenderText)
                    .font(Theme.Typography.subheadline)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .onSubmit {
                        viewModel.addSenderToWhitelist()
                    }
                    .accessibilityLabel("New sender email address")

                Button {
                    viewModel.addSenderToWhitelist()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(
                            viewModel.newSenderText.isEmpty
                                ? Theme.Colors.textSecondary
                                : Theme.Colors.primary
                        )
                }
                .disabled(viewModel.newSenderText.isEmpty)
                .accessibilityLabel("Add sender to whitelist")
            }
        } header: {
            Text("Sender Whitelist")
        } footer: {
            Text("Only scan emails from these senders. Leave empty to scan all senders.")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Full Inbox Section

    @ViewBuilder
    private var fullInboxSection: some View {
        Section {
            Toggle("Scan Full Inbox", isOn: Binding(
                get: { viewModel.scanFullInbox },
                set: { viewModel.toggleFullInbox($0) }
            ))
            .accessibilityLabel("Scan full inbox toggle")
            .accessibilityHint("When enabled, scans all emails instead of just selected labels")
        } header: {
            Text("Full Inbox")
        } footer: {
            if viewModel.scanFullInbox {
                Label(
                    "Full inbox scan enabled. This may take longer and use more AI quota.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.warning)
            } else {
                Text("Enable to scan all emails, not just selected labels.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .alert("Full Inbox Scan", isPresented: $viewModel.showFullInboxWarning) {
            Button("Scan Full Inbox", role: .destructive) {
                viewModel.confirmFullInboxScan()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Scanning your full inbox may take longer and will process all emails, not just promotions. This may use more AI API quota.")
        }
    }

    // MARK: - Date Filter Section

    @ViewBuilder
    private var dateFilterSection: some View {
        Section {
            Toggle("Filter by Date", isOn: Binding(
                get: { viewModel.sinceDate != nil },
                set: { enabled in
                    if enabled {
                        viewModel.sinceDate = Calendar.current.date(
                            byAdding: .month, value: -3, to: Date()
                        )
                    } else {
                        viewModel.sinceDate = nil
                    }
                }
            ))
            .accessibilityLabel("Filter emails by date")

            if viewModel.sinceDate != nil {
                DatePicker(
                    "Since",
                    selection: Binding(
                        get: { viewModel.sinceDate ?? Date() },
                        set: { viewModel.sinceDate = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityLabel("Scan emails since date")
            }
        } header: {
            Text("Date Filter")
        } footer: {
            Text("Only scan emails received on or after the selected date.")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - PrimaryButtonStyle

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.primary.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
    }
}

// MARK: - OutlineButtonStyle

private struct OutlineButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(color)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(color.opacity(configuration.isPressed ? 0.5 : 1.0), lineWidth: 1.5)
            )
    }
}

// MARK: - View+CardStyle

private extension View {
    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Email Scan - Disconnected") {
    NavigationStack {
        EmailScanView()
            .modelContainer(for: DVG.self, inMemory: true)
    }
}
#endif
