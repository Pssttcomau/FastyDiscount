import SwiftUI
import SwiftData
import PassKit

// MARK: - DVGDetailViewModel

/// ViewModel for the DVG detail screen. Manages barcode generation, user actions
/// (mark as used, favourite toggle, balance updates), Apple Wallet pass operations,
/// and transient UI state such as the "Copied!" toast and confirmation alerts.
///
/// Requires a `DVGRepository` for persistence operations. The DVG instance is
/// observed directly via SwiftData's change tracking.
@Observable
@MainActor
final class DVGDetailViewModel {

    // MARK: - Properties

    /// The DVG being displayed. Observed by SwiftData for live updates.
    let dvg: DVG

    /// Repository used for persistence operations.
    private let repository: any DVGRepository

    /// Service for Apple Wallet pass operations.
    private let passKitService: any PassKitService

    /// Generated barcode image, rendered once and cached.
    private(set) var barcodeImage: UIImage?

    /// Whether the barcode is currently being generated.
    private(set) var isGeneratingBarcode: Bool = false

    /// Whether the "Copied!" toast overlay is visible.
    var showCopiedToast: Bool = false

    /// Whether the "Mark as Used" confirmation alert is shown.
    var showMarkAsUsedAlert: Bool = false

    /// Whether the "Record Usage" sheet is shown (gift cards / loyalty).
    var showRecordUsageSheet: Bool = false

    /// The amount to deduct entered by the user in the "Record Usage" sheet.
    var usageAmountText: String = ""

    /// Whether a repository operation is in progress.
    private(set) var isProcessing: Bool = false

    /// Error message to display, if any.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    /// Whether the share sheet is presented.
    var showShareSheet: Bool = false

    // MARK: - Apple Wallet Properties

    /// Whether a wallet pass operation is in progress.
    private(set) var isWalletProcessing: Bool = false

    /// Whether a pass for this DVG is currently in the user's wallet.
    private(set) var isPassInWallet: Bool = false

    /// Whether the "Remove from Wallet" confirmation alert is shown.
    var showRemovePassAlert: Bool = false

    /// Whether the device supports adding passes to Apple Wallet.
    let canAddPasses: Bool

    /// Whether this DVG is eligible for an Apple Wallet pass.
    var isWalletEligible: Bool {
        let snapshot = DVGPassSnapshot(dvg: dvg)
        return snapshot.isWalletEligible
    }

    // MARK: - Init

    init(
        dvg: DVG,
        repository: any DVGRepository,
        passKitService: (any PassKitService)? = nil
    ) {
        self.dvg = dvg
        self.repository = repository
        self.passKitService = passKitService ?? AppleWalletPassKitService()
        self.canAddPasses = AppleWalletPassKitService.canAddPasses()
    }

    // MARK: - Barcode Generation

    /// Generates the barcode image from the DVG's decoded barcode value.
    /// Called once when the view appears. If `barcodeImageData` exists,
    /// that is used as the primary image instead.
    func generateBarcode() async {
        guard barcodeImage == nil, !isGeneratingBarcode else { return }

        isGeneratingBarcode = true

        // Prefer the original scanned barcode image if available
        if let imageData = dvg.barcodeImageData, let image = UIImage(data: imageData) {
            barcodeImage = image
            isGeneratingBarcode = false
            return
        }

        // Generate from decoded value using CIFilter
        let value = dvg.decodedBarcodeValue.isEmpty ? dvg.code : dvg.decodedBarcodeValue
        let type = dvg.barcodeTypeEnum

        guard type != .text, !value.isEmpty else {
            isGeneratingBarcode = false
            return
        }

        // Determine appropriate size based on barcode type
        let size: CGSize
        switch type {
        case .qr:
            size = CGSize(width: 250, height: 250)
        case .pdf417:
            size = CGSize(width: 300, height: 120)
        case .upcA, .upcE, .ean8, .ean13, .code128, .code39:
            size = CGSize(width: 300, height: 120)
        case .text:
            size = .zero
        }

        barcodeImage = BarcodeGenerator.generateBarcode(from: value, type: type, size: size)
        isGeneratingBarcode = false
    }

    // MARK: - Copy Code

    /// Copies the code to the clipboard and shows a brief toast.
    func copyCode() {
        let codeToCopy = dvg.code.isEmpty ? dvg.decodedBarcodeValue : dvg.code
        guard !codeToCopy.isEmpty else { return }

        UIPasteboard.general.string = codeToCopy
        showCopiedToast = true

        // Auto-dismiss the toast after 1.5 seconds
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopiedToast = false
        }
    }

    // MARK: - Mark as Used

    /// Marks the DVG as used via the repository.
    func markAsUsed() async {
        guard !isProcessing else { return }
        isProcessing = true

        do {
            try await repository.markAsUsed(dvg)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isProcessing = false
    }

    // MARK: - Toggle Favourite

    /// Toggles the favourite status of the DVG.
    func toggleFavorite() async {
        dvg.isFavorite.toggle()
        dvg.lastModified = Date()

        // The model context will persist the change on the next save.
        // We do not call repository.save() here because the DVG is already
        // managed by SwiftData and changes are tracked automatically.
    }

    // MARK: - Record Usage (Gift Card / Loyalty)

    /// Deducts the entered amount from the DVG's balance.
    /// For gift cards: deducts from `remainingBalance`.
    /// For loyalty points: deducts from `pointsBalance`.
    func recordUsage() async {
        guard !isProcessing else { return }

        let amountString = usageAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(amountString), amount > 0 else {
            errorMessage = String(localized: "dvgDetail.recordUsage.invalidAmount.error")
            showError = true
            return
        }

        let currentBalance: Double
        if dvg.dvgTypeEnum == .loyaltyPoints {
            currentBalance = dvg.pointsBalance
        } else {
            currentBalance = dvg.remainingBalance
        }

        let newBalance = max(currentBalance - amount, 0)

        isProcessing = true

        do {
            try await repository.updateBalance(dvg, newBalance: newBalance)
            usageAmountText = ""
            showRecordUsageSheet = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isProcessing = false
    }

    // MARK: - Apple Wallet

    /// Checks whether a pass for this DVG is in the user's wallet.
    /// Called on view appear to set initial wallet button state.
    func checkWalletStatus() {
        guard canAddPasses, isWalletEligible else {
            isPassInWallet = false
            return
        }

        let snapshot = DVGPassSnapshot(dvg: dvg)
        isPassInWallet = passKitService.isPassAdded(for: snapshot)
    }

    /// Generates a pass for the DVG and attempts to add it to Apple Wallet.
    ///
    /// In v1, this generates the full pass data structure but will surface a
    /// message about signing requirements since client-side `.pkpass` signing
    /// is not yet implemented.
    func addToWallet() async {
        guard !isWalletProcessing else { return }
        isWalletProcessing = true
        defer { isWalletProcessing = false }

        let snapshot = DVGPassSnapshot(dvg: dvg)

        do {
            let passData = try passKitService.generatePass(for: snapshot)
            try await passKitService.addPass(passData)
            isPassInWallet = true
        } catch let error as PassKitServiceError {
            switch error {
            case .signingRequired:
                // Expected in v1: pass data was generated successfully but
                // signing infrastructure is not yet available.
                errorMessage = String(localized: "dvgDetail.wallet.signingRequired.error")
                showError = true
            default:
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Removes the wallet pass for this DVG from Apple Wallet.
    func removeFromWallet() {
        guard canAddPasses else { return }

        let snapshot = DVGPassSnapshot(dvg: dvg)

        do {
            try passKitService.removePass(for: snapshot)
            isPassInWallet = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Suggests removing the pass when a DVG is marked as used or expired.
    /// Returns `true` if a pass exists that should be removed.
    func shouldSuggestPassRemoval() -> Bool {
        guard canAddPasses else { return false }
        let snapshot = DVGPassSnapshot(dvg: dvg)
        return passKitService.isPassAdded(for: snapshot)
    }

    // MARK: - Share Content

    /// The items to share via the share sheet.
    var shareItems: [Any] {
        var items: [Any] = []

        let codeText = dvg.code.isEmpty ? dvg.decodedBarcodeValue : dvg.code
        var shareText = dvg.title

        if !dvg.storeName.isEmpty {
            shareText += " at \(dvg.storeName)"
        }

        if !codeText.isEmpty {
            shareText += "\nCode: \(codeText)"
        }

        items.append(shareText)

        return items
    }

    // MARK: - Computed Display Properties

    /// The code value to display prominently.
    var displayCode: String {
        let code = dvg.code.isEmpty ? dvg.decodedBarcodeValue : dvg.code
        return code.isEmpty ? String(localized: "dvgDetail.code.noCode") : code
    }

    /// Whether the DVG has a copyable code.
    var hasCode: Bool {
        !dvg.code.isEmpty || !dvg.decodedBarcodeValue.isEmpty
    }

    /// Whether the DVG is a gift card or loyalty type that supports balance tracking.
    var supportsBalance: Bool {
        dvg.dvgTypeEnum == .giftCard || dvg.dvgTypeEnum == .loyaltyPoints
    }

    /// The current balance formatted for display using locale-aware formatters.
    var formattedBalance: String {
        if dvg.dvgTypeEnum == .loyaltyPoints {
            let formatted = LocaleFormatters.integer(for: Int(dvg.pointsBalance))
            return String(format: String(localized: "dvgDetail.balance.pointsFormat"), formatted)
        } else {
            return LocaleFormatters.currency(for: dvg.remainingBalance)
        }
    }

    /// The original value formatted for display using a locale-aware currency formatter.
    var formattedOriginalValue: String {
        LocaleFormatters.currency(for: dvg.originalValue)
    }

    /// The minimum spend formatted for display using a locale-aware currency formatter.
    var formattedMinimumSpend: String {
        LocaleFormatters.currency(for: dvg.minimumSpend)
    }

    /// Color for the expiry date indicator.
    var expiryColor: Color {
        guard let days = dvg.daysUntilExpiry else { return Theme.Colors.textSecondary }

        if days < 0 {
            return Theme.Colors.error
        } else if days < 3 {
            return Theme.Colors.error
        } else if days <= 7 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.success
        }
    }

    /// Human-readable expiry description using locale-aware date formatting.
    var expiryDescription: String {
        guard let expirationDate = dvg.expirationDate else {
            return String(localized: "No expiration", comment: "Shown when a DVG has no expiration date set")
        }

        let dateString = LocaleFormatters.abbreviatedDate.string(from: expirationDate)

        if let days = dvg.daysUntilExpiry {
            if days < 0 {
                return String(localized: "Expired on \(dateString)", comment: "Expiry description when the item has already expired. %@ is the formatted expiry date.")
            } else if days == 0 {
                return String(localized: "Expires today", comment: "Expiry description when the item expires on the current day")
            } else if days == 1 {
                return String(localized: "Expires tomorrow", comment: "Expiry description when the item expires tomorrow")
            } else {
                return String(localized: "Expires in \(days) days (\(dateString))", comment: "Expiry description showing remaining days and date. First %d is days, second %@ is the formatted date.")
            }
        }

        return dateString
    }

    /// Whether the DVG has store locations to show on the map.
    var hasStoreLocations: Bool {
        guard let locations = dvg.storeLocations else { return false }
        return locations.contains { !$0.isDeleted && $0.latitude != 0 && $0.longitude != 0 }
    }

    /// Non-deleted store locations with valid coordinates.
    var activeStoreLocations: [StoreLocation] {
        (dvg.storeLocations ?? []).filter { !$0.isDeleted && $0.latitude != 0 && $0.longitude != 0 }
    }

    /// Non-deleted tags.
    var activeTags: [Tag] {
        (dvg.tags ?? []).filter { !$0.isDeleted }
    }

    /// Formatted date added string using a locale-aware formatter.
    var formattedDateAdded: String {
        LocaleFormatters.mediumDateShortTime.string(from: dvg.dateAdded)
    }

    /// The balance label used in the Record Usage sheet.
    var balanceLabel: String {
        dvg.dvgTypeEnum == .loyaltyPoints
            ? String(localized: "dvgDetail.balance.label.points")
            : String(localized: "dvgDetail.balance.label.balance")
    }
}
