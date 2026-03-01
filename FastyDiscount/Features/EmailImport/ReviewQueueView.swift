import SwiftData
import SwiftUI

// MARK: - ReviewQueueView

/// Displays all DVGs that have a low-confidence email extraction and need
/// human review before being accepted into the wallet.
///
/// Each item shows extracted fields, an overall confidence score (color-coded),
/// an expandable original email snippet, and action buttons to approve, edit,
/// or discard the extraction.
///
/// Batch actions ("Approve All" / "Discard All") are available via the toolbar
/// when the queue is non-empty.
struct ReviewQueueView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router

    // MARK: - State

    @State private var viewModel: ReviewQueueViewModel?

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
        .navigationTitle("Review Queue")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if viewModel == nil {
                let repo = SwiftDataDVGRepository(modelContext: modelContext)
                viewModel = ReviewQueueViewModel(repository: repo, modelContext: modelContext)
            }
            await viewModel!.loadReviewQueue()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(viewModel: ReviewQueueViewModel) -> some View {
        @Bindable var vm = viewModel

        Group {
            if viewModel.isLoading {
                loadingView()
            } else if viewModel.items.isEmpty {
                emptyStateView()
            } else {
                queueListView(viewModel: viewModel)
            }
        }
        .toolbar {
            if !viewModel.items.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    batchActionsMenu(viewModel: viewModel)
                }
            }
        }
        .alert("Approve All Items", isPresented: $vm.showApproveAllConfirmation) {
            Button("Approve All") { viewModel.approveAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(viewModel.pendingCount) items will be accepted as-is and moved to your wallet.")
        }
        .alert("Discard All Items", isPresented: $vm.showDiscardAllConfirmation) {
            Button("Discard All", role: .destructive) { viewModel.discardAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(viewModel.pendingCount) items will be permanently removed.")
        }
        .alert("Error", isPresented: $vm.hasError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private func loadingView() -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.primary)
            Text("Loading review queue...")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    @ViewBuilder
    private func emptyStateView() -> some View {
        ContentUnavailableView(
            "All Caught Up",
            systemImage: "checkmark.circle.fill",
            description: Text("No email extractions are waiting for review.")
        )
        .foregroundStyle(Theme.Colors.success)
    }

    // MARK: - Queue List View

    @ViewBuilder
    private func queueListView(viewModel: ReviewQueueViewModel) -> some View {
        List {
            ForEach(viewModel.items) { dvg in
                ReviewQueueItemView(dvg: dvg) { action in
                    handleAction(action, dvg: dvg, viewModel: viewModel)
                }
                .listRowInsets(EdgeInsets(
                    top: Theme.Spacing.sm,
                    leading: Theme.Spacing.md,
                    bottom: Theme.Spacing.sm,
                    trailing: Theme.Spacing.md
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.discard(dvg)
                    } label: {
                        Label("Discard", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        viewModel.approve(dvg)
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .tint(Theme.Colors.success)
                }
            }
        }
        .listStyle(.plain)
        .background(Theme.Colors.background)
        .refreshable {
            await viewModel.loadReviewQueue()
        }
    }

    // MARK: - Batch Actions Menu

    @ViewBuilder
    private func batchActionsMenu(viewModel: ReviewQueueViewModel) -> some View {
        Menu {
            Button {
                viewModel.showApproveAllConfirmation = true
            } label: {
                Label("Approve All", systemImage: "checkmark.circle.fill")
            }

            Button(role: .destructive) {
                viewModel.showDiscardAllConfirmation = true
            } label: {
                Label("Discard All", systemImage: "trash.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Batch actions")
        }
    }

    // MARK: - Action Handler

    private func handleAction(
        _ action: ReviewQueueItemAction,
        dvg: DVG,
        viewModel: ReviewQueueViewModel
    ) {
        switch action {
        case .approve:
            viewModel.approve(dvg)
        case .edit:
            router.push(.dvgEdit(dvg.id))
        case .discard:
            viewModel.discard(dvg)
        }
    }
}

// MARK: - ReviewQueueItemAction

/// Actions that can be triggered from a `ReviewQueueItemView`.
enum ReviewQueueItemAction {
    case approve
    case edit
    case discard
}

// MARK: - ReviewQueueItemView

/// A card-style row in the review queue that displays the extracted DVG fields,
/// a color-coded confidence score, and an expandable original email snippet.
private struct ReviewQueueItemView: View {

    // MARK: - Properties

    let dvg: DVG
    let onAction: (ReviewQueueItemAction) -> Void

    @State private var isEmailExpanded: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            headerRow
            Divider().background(Theme.Colors.border)
            fieldsSection
            if let scanResult = dvg.scanResult, !scanResult.rawText.isEmpty {
                Divider().background(Theme.Colors.border)
                emailSnippetSection(scanResult: scanResult)
            }
            Divider().background(Theme.Colors.border)
            actionButtonsRow
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Header Row

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(dvg.title.isEmpty ? "Untitled Extraction" : dvg.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                if !dvg.storeName.isEmpty {
                    Label(dvg.storeName, systemImage: "storefront.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            confidenceBadge
        }
    }

    // MARK: - Confidence Badge

    @ViewBuilder
    private var confidenceBadge: some View {
        let score = dvg.scanResult?.confidenceScore ?? 0.0
        let color = confidenceColor(for: score)
        let percentage = Int(score * 100)

        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text("\(percentage)%")
                .font(Theme.Typography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Confidence score: \(percentage) percent")
    }

    // MARK: - Fields Section

    @ViewBuilder
    private var fieldsSection: some View {
        let confidences = dvg.scanResult?.fieldConfidencesDict ?? [:]

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !dvg.code.isEmpty {
                fieldRow(
                    label: "Code",
                    value: dvg.code,
                    icon: "number.square.fill",
                    confidence: confidences["code"]
                )
            }

            fieldRow(
                label: "Type",
                value: dvg.dvgTypeEnum.displayName,
                icon: "tag.fill",
                confidence: confidences["dvgType"]
            )

            if let expiry = dvg.expirationDate {
                fieldRow(
                    label: "Expires",
                    value: expiry.formatted(date: .abbreviated, time: .omitted),
                    icon: "calendar",
                    confidence: confidences["expirationDate"]
                )
            }
        }
    }

    @ViewBuilder
    private func fieldRow(
        label: String,
        value: String,
        icon: String,
        confidence: Double? = nil
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 16)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            if let confidence {
                Circle()
                    .fill(confidenceColor(for: confidence))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(
                        "Field confidence: \(Int(confidence * 100)) percent"
                    )
            }
        }
    }

    // MARK: - Email Snippet Section

    @ViewBuilder
    private func emailSnippetSection(scanResult: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEmailExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "envelope.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        if !scanResult.emailSubject.isEmpty {
                            Text(scanResult.emailSubject)
                                .font(Theme.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        if !scanResult.emailSender.isEmpty {
                            Text(scanResult.emailSender)
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: isEmailExpanded ? "chevron.up" : "chevron.down")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEmailExpanded ? "Collapse email snippet" : "Expand email snippet")

            if isEmailExpanded {
                Text(scanResult.rawText)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(8)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(Theme.Colors.background)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Action Buttons Row

    @ViewBuilder
    private var actionButtonsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Discard button
            Button(role: .destructive) {
                onAction(.discard)
            } label: {
                Label("Discard", systemImage: "trash")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
            }
            .buttonStyle(ReviewActionButtonStyle(color: Theme.Colors.error))
            .accessibilityLabel("Discard this extraction")

            Spacer()

            // Edit button
            Button {
                onAction(.edit)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.primary)
            }
            .buttonStyle(ReviewActionButtonStyle(color: Theme.Colors.primary))
            .accessibilityLabel("Edit this extraction before saving")

            // Approve button
            Button {
                onAction(.approve)
            } label: {
                Label("Approve", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white)
            }
            .buttonStyle(ReviewApproveButtonStyle())
            .accessibilityLabel("Approve this extraction as-is")
        }
    }

    // MARK: - Helpers

    /// Returns the color for a given confidence score.
    /// - >= 0.8: green (success)
    /// - 0.5 ..< 0.8: yellow (warning)
    /// - < 0.5: red (error)
    private func confidenceColor(for score: Double) -> Color {
        if score >= 0.8 {
            return Theme.Colors.success
        } else if score >= 0.5 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.error
        }
    }
}

// MARK: - ReviewActionButtonStyle

/// Outline-style button used for "Discard" and "Edit" actions.
private struct ReviewActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .strokeBorder(
                        color.opacity(configuration.isPressed ? 0.5 : 1.0),
                        lineWidth: 1.0
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - ReviewApproveButtonStyle

/// Filled button style used for the "Approve" primary action.
private struct ReviewApproveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(Theme.Colors.success.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Review Queue - Items") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DVG.self, ScanResult.self, configurations: config)

    // Create sample DVGs with ScanResults
    let context = container.mainContext

    let dvg1 = DVG(
        title: "20% off your first order",
        code: "WELCOME20",
        dvgType: .discountCode,
        storeName: "FashionStore",
        expirationDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
        source: .email,
        status: .active
    )
    let scan1 = ScanResult(
        sourceType: .email,
        rawText: "Thank you for signing up! Use code WELCOME20 at checkout to receive 20% off your first order. Valid until end of month. T&Cs apply.",
        confidenceScore: 0.72,
        needsReview: true,
        emailSubject: "Welcome to FashionStore - Your discount awaits",
        emailSender: "noreply@fashionstore.com"
    )
    context.insert(dvg1)
    context.insert(scan1)
    dvg1.scanResult = scan1

    let dvg2 = DVG(
        title: "Gift Card",
        code: "GC-XMAS-2024",
        dvgType: .giftCard,
        storeName: "TechShop",
        originalValue: 50.0,
        remainingBalance: 50.0,
        source: .email,
        status: .active
    )
    let scan2 = ScanResult(
        sourceType: .email,
        rawText: "You have received a $50 gift card. Your code is GC-XMAS-2024.",
        confidenceScore: 0.43,
        needsReview: true,
        emailSubject: "Your TechShop Gift Card",
        emailSender: "gifts@techshop.com"
    )
    context.insert(dvg2)
    context.insert(scan2)
    dvg2.scanResult = scan2

    return NavigationStack {
        ReviewQueueView()
            .modelContainer(container)
            .environment(NavigationRouter())
    }
}

#Preview("Review Queue - Empty") {
    NavigationStack {
        ReviewQueueView()
            .modelContainer(for: DVG.self, inMemory: true)
            .environment(NavigationRouter())
    }
}
#endif
