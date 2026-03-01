import SwiftUI
import SwiftData

// MARK: - DVGDetailViewModel

/// ViewModel for the DVG detail screen. Manages barcode generation, user actions
/// (mark as used, favourite toggle, balance updates), and transient UI state
/// such as the "Copied!" toast and confirmation alerts.
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

    // MARK: - Init

    init(dvg: DVG, repository: any DVGRepository) {
        self.dvg = dvg
        self.repository = repository
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
        case .upcA, .upcE, .ean8, .ean13:
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
            errorMessage = "Please enter a valid positive amount."
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
        return code.isEmpty ? "No code" : code
    }

    /// Whether the DVG has a copyable code.
    var hasCode: Bool {
        !dvg.code.isEmpty || !dvg.decodedBarcodeValue.isEmpty
    }

    /// Whether the DVG is a gift card or loyalty type that supports balance tracking.
    var supportsBalance: Bool {
        dvg.dvgTypeEnum == .giftCard || dvg.dvgTypeEnum == .loyaltyPoints
    }

    /// The current balance formatted for display.
    var formattedBalance: String {
        if dvg.dvgTypeEnum == .loyaltyPoints {
            return "\(Int(dvg.pointsBalance)) points"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            return formatter.string(from: NSNumber(value: dvg.remainingBalance))
                ?? String(format: "$%.2f", dvg.remainingBalance)
        }
    }

    /// The original value formatted for display.
    var formattedOriginalValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dvg.originalValue))
            ?? String(format: "$%.2f", dvg.originalValue)
    }

    /// The minimum spend formatted for display.
    var formattedMinimumSpend: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dvg.minimumSpend))
            ?? String(format: "$%.2f", dvg.minimumSpend)
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

    /// Human-readable expiry description.
    var expiryDescription: String {
        guard let expirationDate = dvg.expirationDate else {
            return "No expiration"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let dateString = formatter.string(from: expirationDate)

        if let days = dvg.daysUntilExpiry {
            if days < 0 {
                return "Expired on \(dateString)"
            } else if days == 0 {
                return "Expires today"
            } else if days == 1 {
                return "Expires tomorrow"
            } else {
                return "Expires in \(days) days (\(dateString))"
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

    /// Formatted date added string.
    var formattedDateAdded: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dvg.dateAdded)
    }

    /// The balance label used in the Record Usage sheet.
    var balanceLabel: String {
        dvg.dvgTypeEnum == .loyaltyPoints ? "Points" : "Balance"
    }
}
