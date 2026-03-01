import SwiftUI
import SwiftData
import MapKit

// MARK: - DVGDetailView

/// Full detail view for a DVG item. Displays barcode, code, details, store locations,
/// notes/terms, and an action toolbar. Supports adaptive layout for iPhone and iPad.
///
/// The view receives a DVG UUID via navigation and fetches the model from SwiftData.
struct DVGDetailView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var router

    // MARK: - State

    @State private var viewModel: DVGDetailViewModel?

    /// The DVG UUID passed via navigation.
    let dvgID: UUID

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                detailContent(viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    "Item Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This discount item could not be found.")
                )
            }
        }
        .navigationTitle(viewModel?.dvg.title ?? "Detail")
        .navigationBarTitleDisplayMode(.large)
        .task {
            loadDVG()
        }
    }

    // MARK: - Load DVG

    private func loadDVG() {
        guard viewModel == nil else { return }

        let id = dvgID
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> { $0.id == id && $0.isDeleted == false }
        )

        guard let dvg = try? modelContext.fetch(descriptor).first else { return }

        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        viewModel = DVGDetailViewModel(dvg: dvg, repository: repository)

        Task {
            await viewModel?.generateBarcode()
        }

        viewModel?.checkWalletStatus()
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(viewModel: DVGDetailViewModel) -> some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                // iPad: side-by-side layout
                iPadLayout(viewModel: viewModel)
            } else {
                // iPhone: single-column layout
                iPhoneLayout(viewModel: viewModel)
            }
        }
        .background(Theme.Colors.background)
        .overlay(alignment: .top) {
            copiedToastOverlay(viewModel: viewModel)
        }
        .toolbar {
            actionToolbar(viewModel: viewModel)
        }
        .alert("Mark as Used", isPresented: bindable(viewModel).showMarkAsUsedAlert) {
            Button("Mark as Used", role: .destructive) {
                Task { await viewModel.markAsUsed() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to mark this item as used? This action cannot be undone.")
        }
        .sheet(isPresented: bindable(viewModel).showRecordUsageSheet) {
            recordUsageSheet(viewModel: viewModel)
        }
        .sheet(isPresented: bindable(viewModel).showShareSheet) {
            ShareSheet(items: viewModel.shareItems)
        }
        .alert("Error", isPresented: bindable(viewModel).showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .alert("Remove from Wallet", isPresented: bindable(viewModel).showRemovePassAlert) {
            Button("Remove", role: .destructive) {
                viewModel.removeFromWallet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Remove this pass from Apple Wallet?")
        }
    }

    // MARK: - iPhone Layout

    @ViewBuilder
    private func iPhoneLayout(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            statusBadge(viewModel: viewModel)
            barcodeSection(viewModel: viewModel)
            walletSection(viewModel: viewModel)
            codeDisplaySection(viewModel: viewModel)
            detailsSection(viewModel: viewModel)

            if viewModel.supportsBalance {
                balanceSection(viewModel: viewModel)
            }

            if viewModel.hasStoreLocations {
                storeLocationSection(viewModel: viewModel)
            }

            if !viewModel.activeTags.isEmpty {
                tagsSection(viewModel: viewModel)
            }

            notesAndTermsSection(viewModel: viewModel)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - iPad Layout

    @ViewBuilder
    private func iPadLayout(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            statusBadge(viewModel: viewModel)

            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                // Left column: barcode + code + wallet
                VStack(spacing: Theme.Spacing.md) {
                    barcodeSection(viewModel: viewModel)
                    walletSection(viewModel: viewModel)
                    codeDisplaySection(viewModel: viewModel)

                    if viewModel.supportsBalance {
                        balanceSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity)

                // Right column: details, map, tags, notes
                VStack(spacing: Theme.Spacing.md) {
                    detailsSection(viewModel: viewModel)

                    if viewModel.hasStoreLocations {
                        storeLocationSection(viewModel: viewModel)
                    }

                    if !viewModel.activeTags.isEmpty {
                        tagsSection(viewModel: viewModel)
                    }

                    notesAndTermsSection(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(viewModel: DVGDetailViewModel) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(viewModel.dvg.statusColor)
                .frame(width: 10, height: 10)

            Text(viewModel.dvg.statusEnum.displayName)
                .font(Theme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(viewModel.dvg.statusColor)

            Spacer()

            Text(viewModel.dvg.dvgTypeEnum.displayName)
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.primary.opacity(0.12))
                .foregroundStyle(Theme.Colors.primary)
                .clipShape(Capsule())

            if viewModel.dvg.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(Theme.Typography.subheadline)
                    .accessibilityLabel("Favourited")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Status: \(viewModel.dvg.statusEnum.displayName), Type: \(viewModel.dvg.dvgTypeEnum.displayName)"
            + (viewModel.dvg.isFavorite ? ", favourited" : "")
        )
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAddTraits(.isSummaryElement)
    }

    // MARK: - Barcode Section

    @ViewBuilder
    private func barcodeSection(viewModel: DVGDetailViewModel) -> some View {
        if viewModel.dvg.barcodeTypeEnum != .text {
            VStack(spacing: Theme.Spacing.sm) {
                sectionHeader("Barcode")

                if viewModel.isGeneratingBarcode {
                    ProgressView("Generating barcode...")
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                } else if let image = viewModel.barcodeImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 200)
                        .padding(Theme.Spacing.md)
                        .accessibilityLabel("Barcode displayed for \(viewModel.dvg.storeName.isEmpty ? viewModel.dvg.title : viewModel.dvg.storeName). Show to cashier.")
                        .accessibilityHint("Shows the scannable barcode. Code value: \(viewModel.displayCode)")
                } else {
                    ContentUnavailableView {
                        Label("Barcode Unavailable", systemImage: "barcode.viewfinder")
                    } description: {
                        Text("Unable to generate barcode image.")
                    }
                    .frame(height: 120)
                }

                Text(viewModel.dvg.barcodeTypeEnum.displayName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel("Barcode type: \(viewModel.dvg.barcodeTypeEnum.displayName)")
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
        }
    }

    // MARK: - Code Display Section

    @ViewBuilder
    private func codeDisplaySection(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            sectionHeader("Code")

            Button {
                viewModel.copyCode()
            } label: {
                HStack {
                    Text(viewModel.displayCode)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)

                    if viewModel.hasCode {
                        Image(systemName: "doc.on.doc")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
            }
            .disabled(!viewModel.hasCode)
            .accessibilityLabel("Code: \(viewModel.displayCode)")
            .accessibilityHint(viewModel.hasCode ? "Double-tap to copy to clipboard" : "")
            .accessibilityAddTraits(viewModel.hasCode ? .isButton : [])
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            sectionHeader("Details")

            VStack(spacing: Theme.Spacing.md) {
                if !viewModel.dvg.storeName.isEmpty {
                    detailRow(
                        icon: "storefront",
                        label: "Store",
                        value: viewModel.dvg.storeName
                    )
                }

                if !viewModel.dvg.discountDescription.isEmpty {
                    detailRow(
                        icon: "text.alignleft",
                        label: "Description",
                        value: viewModel.dvg.discountDescription
                    )
                }

                if viewModel.dvg.originalValue > 0 {
                    detailRow(
                        icon: "dollarsign.circle",
                        label: "Value",
                        value: viewModel.dvg.displayValue
                    )
                }

                if viewModel.dvg.minimumSpend > 0 {
                    detailRow(
                        icon: "cart",
                        label: "Minimum Spend",
                        value: viewModel.formattedMinimumSpend
                    )
                }

                // Expiry with color coding
                if viewModel.dvg.expirationDate != nil {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(Theme.Typography.body)
                            .foregroundStyle(viewModel.expiryColor)
                            .frame(width: 24, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Expiry")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(viewModel.expiryDescription)
                                .font(Theme.Typography.body)
                                .foregroundStyle(viewModel.expiryColor)
                                .fontWeight(.medium)
                        }

                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Expiry: \(viewModel.expiryDescription)")
                }

                detailRow(
                    icon: "plus.circle",
                    label: "Added",
                    value: viewModel.formattedDateAdded
                )

                detailRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Source",
                    value: viewModel.dvg.sourceEnum.displayName
                )
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Balance Section

    @ViewBuilder
    private func balanceSection(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            sectionHeader(viewModel.balanceLabel)

            VStack(spacing: Theme.Spacing.md) {
                Text(viewModel.formattedBalance)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.primary)
                    .accessibilityLabel("\(viewModel.balanceLabel): \(viewModel.formattedBalance)")

                if viewModel.dvg.dvgTypeEnum == .giftCard && viewModel.dvg.originalValue > 0 {
                    Text("of \(viewModel.formattedOriginalValue) original")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Button {
                    viewModel.showRecordUsageSheet = true
                } label: {
                    Label("Record Usage", systemImage: "minus.circle")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.primary)
                .disabled(viewModel.dvg.statusEnum != .active)
                .accessibilityLabel("Record Usage")
                .accessibilityHint("Opens a sheet to record spending or point usage")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Store Location Section

    @ViewBuilder
    private func storeLocationSection(viewModel: DVGDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            sectionHeader("Store Location")

            let locations = viewModel.activeStoreLocations

            Map {
                ForEach(locations, id: \.id) { location in
                    Marker(
                        location.name.isEmpty ? "Store" : location.name,
                        coordinate: location.coordinate
                    )
                    .tint(Theme.Colors.primary)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            .allowsHitTesting(false)
            .accessibilityLabel("Map showing \(locations.count) store location\(locations.count == 1 ? "" : "s") for \(viewModel.dvg.storeName.isEmpty ? viewModel.dvg.title : viewModel.dvg.storeName)")
            .accessibilityAddTraits(.isImage)

            ForEach(locations, id: \.id) { location in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.Colors.primary)
                        .font(Theme.Typography.body)

                    VStack(alignment: .leading, spacing: 2) {
                        if !location.name.isEmpty {
                            Text(location.name)
                                .font(Theme.Typography.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        if !location.address.isEmpty {
                            Text(location.address)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(location.name.isEmpty ? "Store" : location.name)"
                    + (location.address.isEmpty ? "" : ", \(location.address)")
                )
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(viewModel: DVGDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Tags")

            FlowLayout(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.activeTags, id: \.id) { tag in
                    TagChip(tag: tag)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Notes & Terms Section

    @ViewBuilder
    private func notesAndTermsSection(viewModel: DVGDetailViewModel) -> some View {
        let hasNotes = !viewModel.dvg.notes.isEmpty
        let hasTerms = !viewModel.dvg.termsAndConditions.isEmpty

        if hasNotes || hasTerms {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if hasNotes {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        sectionHeader("Notes")
                        Text(viewModel.dvg.notes)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }

                if hasNotes && hasTerms {
                    Divider()
                }

                if hasTerms {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        sectionHeader("Terms & Conditions")
                        Text(viewModel.dvg.termsAndConditions)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .cardStyle()
        }
    }

    // MARK: - Wallet Section

    @ViewBuilder
    private func walletSection(viewModel: DVGDetailViewModel) -> some View {
        WalletSection(
            canAddPasses: viewModel.canAddPasses,
            isEligible: viewModel.isWalletEligible,
            isAlreadyAdded: viewModel.isPassInWallet,
            isProcessing: viewModel.isWalletProcessing,
            onAddToWallet: {
                Task { await viewModel.addToWallet() }
            },
            onRemoveFromWallet: {
                viewModel.showRemovePassAlert = true
            }
        )
    }

    // MARK: - Action Toolbar

    @ToolbarContentBuilder
    private func actionToolbar(viewModel: DVGDetailViewModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            // Mark as Used
            Button {
                viewModel.showMarkAsUsedAlert = true
            } label: {
                Label("Mark Used", systemImage: "checkmark.circle")
            }
            .disabled(viewModel.dvg.statusEnum != .active || viewModel.isProcessing)
            .accessibilityLabel("Mark as Used")
            .accessibilityHint("Marks this item as redeemed")

            Spacer()

            // Edit
            Button {
                router.push(.dvgEdit(dvgID))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityLabel("Edit")
            .accessibilityHint("Opens the edit form for this item")

            Spacer()

            // Favourite toggle
            Button {
                Task { await viewModel.toggleFavorite() }
            } label: {
                Label(
                    viewModel.dvg.isFavorite ? "Unfavourite" : "Favourite",
                    systemImage: viewModel.dvg.isFavorite ? "heart.fill" : "heart"
                )
            }
            .tint(viewModel.dvg.isFavorite ? .red : nil)
            .accessibilityLabel(viewModel.dvg.isFavorite ? "Remove from favourites" : "Add to favourites")
            .accessibilityHint("Double-tap to toggle favourite status")

            Spacer()

            // Share
            Button {
                viewModel.showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            .accessibilityHint("Opens the share sheet to share this item")
        }
    }

    // MARK: - Copied Toast Overlay

    @ViewBuilder
    private func copiedToastOverlay(viewModel: DVGDetailViewModel) -> some View {
        if viewModel.showCopiedToast {
            Text("Copied!")
                .font(Theme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.success)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.top, Theme.Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.showCopiedToast)
                .accessibilityLabel("Code copied to clipboard")
        }
    }

    // MARK: - Record Usage Sheet

    @ViewBuilder
    private func recordUsageSheet(viewModel: DVGDetailViewModel) -> some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Text(String(format: String(localized: "dvgDetail.recordUsage.currentBalance.label"), viewModel.balanceLabel))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(viewModel.formattedBalance)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.primary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Amount to deduct")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    TextField(
                        viewModel.dvg.dvgTypeEnum == .loyaltyPoints ? "Points" : "Amount",
                        text: bindable(viewModel).usageAmountText
                    )
                    .keyboardType(.decimalPad)
                    .font(.system(.title3, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Amount to deduct")
                    .accessibilityHint("Enter the amount spent or points used")
                }

                Button {
                    Task { await viewModel.recordUsage() }
                } label: {
                    if viewModel.isProcessing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    } else {
                        Text("Record")
                            .font(Theme.Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.primary)
                .disabled(viewModel.isProcessing || viewModel.usageAmountText.isEmpty)
                .accessibilityLabel("Record usage")
                .accessibilityHint("Deducts the entered amount from the balance")

                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("Record Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showRecordUsageSheet = false
                    }
                    .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Tag Chip

/// A small colored pill displaying a tag name.
private struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(Theme.Typography.caption)
            .fontWeight(.medium)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(tagColor.opacity(0.15))
            .foregroundStyle(tagColor)
            .clipShape(Capsule())
            .accessibilityLabel("Tag: \(tag.name)")
    }

    private var tagColor: Color {
        guard let hex = tag.colorHex else {
            return Theme.Colors.accent
        }
        return Color(hex: hex) ?? Theme.Colors.accent
    }
}

// MARK: - FlowLayout

/// A horizontal wrapping layout that arranges children left-to-right, wrapping
/// to the next line when a row is full. Used for tag chips.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct ArrangementResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var totalSize: CGSize
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity

        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return ArrangementResult(
            positions: positions,
            sizes: sizes,
            totalSize: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

/// A UIKit wrapper for `UIActivityViewController` used to present the system share sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Color Hex Extension

extension Color {
    /// Creates a Color from a hex string (e.g. "#FF6B35" or "FF6B35").
    /// Returns `nil` if the string cannot be parsed.
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Binding Helpers

/// Creates `Binding` values from `DVGDetailViewModel` properties.
///
/// Uses the `Bindable` wrapper from the Observation framework to produce
/// two-way bindings suitable for SwiftUI `alert`, `sheet`, and `TextField`
/// modifiers when the view model is passed as a function parameter rather
/// than held in a `@Bindable` property wrapper.
@MainActor
private func bindable(_ viewModel: DVGDetailViewModel) -> Bindable<DVGDetailViewModel> {
    Bindable(viewModel)
}

// MARK: - Preview

#if DEBUG
#Preview("DVG Detail") {
    NavigationStack {
        DVGDetailView(dvgID: DVG.preview.id)
    }
    .environment(NavigationRouter())
    .modelContainer(for: DVG.self, inMemory: true)
}
#endif
