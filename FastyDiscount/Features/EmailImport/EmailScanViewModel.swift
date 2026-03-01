import Foundation
import SwiftData
import SwiftUI

// MARK: - EmailScanState

/// The overall state of the email scan flow.
enum EmailScanState: Equatable {
    /// Idle: no scan in progress.
    case idle
    /// Fetching emails from Gmail API.
    case fetchingEmails
    /// Parsing fetched emails through the AI pipeline.
    case parsing(current: Int, total: Int)
    /// Scan completed successfully.
    case complete
    /// Scan failed with an error.
    case failed(message: String)

    static func == (lhs: EmailScanState, rhs: EmailScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.fetchingEmails, .fetchingEmails): return true
        case (.parsing(let lc, let lt), .parsing(let rc, let rt)): return lc == rc && lt == rt
        case (.complete, .complete): return true
        case (.failed(let lm), .failed(let rm)): return lm == rm
        default: return false
        }
    }
}

// MARK: - EmailItemStatus

/// Status of an individual email during the parsing pipeline.
enum EmailItemStatus: Sendable {
    case pending
    case parsing
    case done(DVGExtractionResult)
    case failed(String)
}

// MARK: - EmailScanSummary

/// Summary produced after a scan completes.
struct EmailScanSummary: Sendable {
    let totalDVGsFound: Int
    let autoSaved: Int
    let needReview: Int
}

// MARK: - EmailScanViewModel

/// ViewModel managing the email scan flow from Gmail fetch through AI parsing.
///
/// Manages:
/// - Gmail connection state
/// - Scan scope settings (persisted in UserDefaults)
/// - The full scan pipeline (fetch -> parse -> save)
/// - Progress tracking via `AsyncStream<EmailParseProgress>`
/// - Cancellation support
@Observable
@MainActor
final class EmailScanViewModel {

    // MARK: - Gmail Connection

    /// Whether Gmail is currently connected (authenticated).
    var isGmailConnected: Bool = false

    /// Whether a Gmail connect/disconnect operation is in progress.
    var isConnecting: Bool = false

    // MARK: - Scan Scope Settings

    /// Labels to filter by (empty means all promotional labels).
    var selectedLabels: [String] = EmailScanViewModel.loadSelectedLabels()

    /// Sender whitelist (only emails from these senders).
    var senderWhitelist: [String] = EmailScanViewModel.loadSenderWhitelist()

    /// When true, scans the full inbox (ignores label filters).
    var scanFullInbox: Bool = EmailScanViewModel.loadScanFullInbox()

    /// Optional date filter: only scan emails received on or after this date.
    var sinceDate: Date? = EmailScanViewModel.loadSinceDate()

    // MARK: - Scope Sheet

    /// Controls whether the scope settings sheet is visible.
    var showScopeSettings: Bool = false

    /// Controls whether the full inbox warning alert is shown.
    var showFullInboxWarning: Bool = false

    // MARK: - Label Picker

    /// Available Gmail labels fetched from the API.
    var availableLabels: [GmailLabel] = []

    /// Whether labels are currently being fetched.
    var isFetchingLabels: Bool = false

    // MARK: - Sender Whitelist Editor

    /// Text being typed for a new sender whitelist entry.
    var newSenderText: String = ""

    // MARK: - Scan Progress

    /// Overall scan state.
    var scanState: EmailScanState = .idle

    /// Status of each individual email being processed.
    var emailStatuses: [EmailItemStatus] = []

    /// Overall progress fraction (0.0 – 1.0).
    var progressFraction: Double = 0.0

    /// Summary produced when a scan completes.
    var scanSummary: EmailScanSummary?

    // MARK: - Error States

    /// Whether an error alert is visible.
    var showError: Bool = false

    /// The error message to display.
    var errorMessage: String = ""

    // MARK: - Dependencies

    private let authService: any GmailAuthService
    private let apiClient: any GmailAPIClient
    private let parsingService: any EmailParsingService

    /// Task handle for the active scan — used for cancellation.
    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    init(
        authService: any GmailAuthService,
        apiClient: any GmailAPIClient,
        parsingService: any EmailParsingService
    ) {
        self.authService = authService
        self.apiClient = apiClient
        self.parsingService = parsingService
        self.isGmailConnected = authService.isAuthenticated
    }

    // MARK: - Gmail Connection

    /// Initiates the Gmail OAuth flow.
    func connectGmail() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await authService.authenticate()
            isGmailConnected = authService.isAuthenticated
        } catch GmailAuthError.userCancelled {
            // User cancelled — no error shown
        } catch {
            presentError(error.localizedDescription)
        }
    }

    /// Disconnects the Gmail account.
    func disconnectGmail() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await authService.disconnect()
            isGmailConnected = authService.isAuthenticated
        } catch {
            presentError(error.localizedDescription)
        }
    }

    // MARK: - Label Fetching

    /// Fetches available Gmail labels for the label picker.
    func fetchAvailableLabels() async {
        guard isGmailConnected, !isFetchingLabels else { return }
        isFetchingLabels = true
        defer { isFetchingLabels = false }

        do {
            let labels = try await apiClient.fetchLabels()
            availableLabels = labels
        } catch {
            // Non-critical — label picker just stays empty
            availableLabels = GmailLabel.defaultLabels
        }
    }

    // MARK: - Scope Persistence

    /// Persists current scope settings to UserDefaults.
    func saveScopeSettings() {
        UserDefaults.standard.set(selectedLabels, forKey: EmailScanViewModel.selectedLabelsKey)
        UserDefaults.standard.set(senderWhitelist, forKey: EmailScanViewModel.senderWhitelistKey)
        UserDefaults.standard.set(scanFullInbox, forKey: EmailScanViewModel.scanFullInboxKey)
        if let date = sinceDate {
            UserDefaults.standard.set(date, forKey: EmailScanViewModel.sinceDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: EmailScanViewModel.sinceDateKey)
        }
    }

    // MARK: - Sender Whitelist

    /// Adds the current `newSenderText` entry to the whitelist.
    func addSenderToWhitelist() {
        let trimmed = newSenderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !senderWhitelist.contains(trimmed) else {
            newSenderText = ""
            return
        }
        senderWhitelist.append(trimmed)
        newSenderText = ""
    }

    /// Removes senders at the given offsets from the whitelist.
    func removeSenders(at offsets: IndexSet) {
        senderWhitelist.remove(atOffsets: offsets)
    }

    // MARK: - Full Inbox Toggle

    /// Called when the user toggles "Scan Full Inbox".
    /// If enabling, shows a warning first.
    func toggleFullInbox(_ newValue: Bool) {
        if newValue {
            showFullInboxWarning = true
        } else {
            scanFullInbox = false
        }
    }

    /// Confirms enabling the full inbox scan after warning acknowledgement.
    func confirmFullInboxScan() {
        scanFullInbox = true
        showFullInboxWarning = false
    }

    // MARK: - Scan Pipeline

    /// Builds the current `EmailScanScope` from the view model settings.
    var currentScope: EmailScanScope {
        EmailScanScope(
            selectedLabels: scanFullInbox ? [] : (selectedLabels.isEmpty ? ["CATEGORY_PROMOTIONS"] : selectedLabels),
            senderWhitelist: senderWhitelist,
            scanFullInbox: scanFullInbox,
            sinceDate: sinceDate
        )
    }

    /// Starts the full email scan pipeline.
    func startScan() {
        guard scanState == .idle || {
            if case .failed = scanState { return true }
            if case .complete = scanState { return true }
            return false
        }() else { return }

        saveScopeSettings()
        resetScanState()

        scanTask = Task { [weak self] in
            await self?.runScanPipeline()
        }
    }

    /// Cancels an in-progress scan.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
        emailStatuses = []
        progressFraction = 0.0
        scanSummary = nil
    }

    // MARK: - Private: Scan Pipeline

    private func resetScanState() {
        scanState = .fetchingEmails
        emailStatuses = []
        progressFraction = 0.0
        scanSummary = nil
    }

    private func runScanPipeline() async {
        // --- Step 1: Validate preconditions ---

        guard isGmailConnected else {
            scanState = .failed(message: "Gmail is not connected. Please connect your Gmail account first.")
            return
        }

        // --- Step 2: Fetch emails ---

        let emails: [RawEmail]
        do {
            var allEmails: [RawEmail] = []
            var pageToken: String? = nil

            repeat {
                if Task.isCancelled { return }
                let page = try await apiClient.fetchEmails(
                    scope: currentScope,
                    maxResults: 50,
                    pageToken: pageToken
                )
                allEmails.append(contentsOf: page.emails)
                pageToken = page.nextPageToken
            } while pageToken != nil

            emails = allEmails
        } catch {
            if Task.isCancelled { return }
            scanState = .failed(message: "Failed to fetch emails: \(error.localizedDescription)")
            return
        }

        if Task.isCancelled { return }

        if emails.isEmpty {
            scanSummary = EmailScanSummary(totalDVGsFound: 0, autoSaved: 0, needReview: 0)
            scanState = .complete
            return
        }

        // Initialise per-email status array
        emailStatuses = Array(repeating: .pending, count: emails.count)

        // --- Step 3: Parse emails through AI pipeline ---

        let stream = parsingService.parseEmails(emails, sinceDate: sinceDate)

        var foundCount = 0
        var autoSavedCount = 0
        var needReviewCount = 0

        for await progress in stream {
            if Task.isCancelled { return }

            switch progress {
            case .parsing(let index, let total):
                scanState = .parsing(current: index + 1, total: total)
                if index < emailStatuses.count {
                    emailStatuses[index] = .parsing
                }
                progressFraction = total > 0 ? Double(index) / Double(total) : 0

            case .parsed(let result):
                // Find the "parsing" index to mark done
                if let idx = emailStatuses.firstIndex(where: { if case .parsing = $0 { return true }; return false }) {
                    emailStatuses[idx] = .done(result)
                }
                foundCount += 1
                if result.confidenceScore >= 0.8 {
                    autoSavedCount += 1
                } else {
                    needReviewCount += 1
                }

            case .failed(let index, let error):
                if index < emailStatuses.count {
                    emailStatuses[index] = .failed(error.localizedDescription)
                }

            case .complete(let results):
                progressFraction = 1.0
                foundCount = results.count
                autoSavedCount = results.filter { $0.confidenceScore >= 0.8 }.count
                needReviewCount = results.filter { $0.confidenceScore < 0.8 }.count
                scanSummary = EmailScanSummary(
                    totalDVGsFound: foundCount,
                    autoSaved: autoSavedCount,
                    needReview: needReviewCount
                )
                scanState = .complete
            }
        }

        if Task.isCancelled { return }

        // If we exit the stream without a .complete event, produce a summary
        if case .complete = scanState {
            // already set above
        } else {
            scanSummary = EmailScanSummary(
                totalDVGsFound: foundCount,
                autoSaved: autoSavedCount,
                needReview: needReviewCount
            )
            scanState = .complete
        }
    }

    // MARK: - Error Presentation

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - UserDefaults Keys

    private static let selectedLabelsKey = "emailScan.selectedLabels"
    private static let senderWhitelistKey = "emailScan.senderWhitelist"
    private static let scanFullInboxKey = "emailScan.scanFullInbox"
    private static let sinceDateKey = "emailScan.sinceDate"

    private static func loadSelectedLabels() -> [String] {
        UserDefaults.standard.stringArray(forKey: selectedLabelsKey) ?? ["CATEGORY_PROMOTIONS"]
    }

    private static func loadSenderWhitelist() -> [String] {
        UserDefaults.standard.stringArray(forKey: senderWhitelistKey) ?? []
    }

    private static func loadScanFullInbox() -> Bool {
        UserDefaults.standard.bool(forKey: scanFullInboxKey)
    }

    private static func loadSinceDate() -> Date? {
        UserDefaults.standard.object(forKey: sinceDateKey) as? Date
    }
}

// MARK: - GmailLabel

/// A Gmail label with ID and display name, used by the label picker.
struct GmailLabel: Identifiable, Sendable, Hashable {
    let id: String
    let name: String

    /// Default well-known Gmail labels.
    static let defaultLabels: [GmailLabel] = [
        GmailLabel(id: "CATEGORY_PROMOTIONS", name: "Promotions"),
        GmailLabel(id: "CATEGORY_UPDATES", name: "Updates"),
        GmailLabel(id: "CATEGORY_SOCIAL", name: "Social"),
        GmailLabel(id: "INBOX", name: "Inbox"),
        GmailLabel(id: "UNREAD", name: "Unread")
    ]
}

// MARK: - GmailAPIClient Extension (fetchLabels)

extension GmailAPIClient {
    /// Fetches the list of Gmail labels for the authenticated user.
    ///
    /// Provides a default implementation that returns the built-in label list
    /// so existing conforming types don't need to implement it immediately.
    func fetchLabels() async throws -> [GmailLabel] {
        return GmailLabel.defaultLabels
    }
}
