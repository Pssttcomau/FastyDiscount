import Foundation
import WatchConnectivity
import SwiftData

// MARK: - WatchConnectivityService

/// Manages Watch Connectivity communication between the iPhone app and the paired Apple Watch.
///
/// ### Responsibilities
/// - Sends active DVG data to the watch via `updateApplicationContext` (latest state; replaces previous).
/// - Receives "mark as used" actions from the watch and applies them via `DVGRepository`.
/// - Activates the WCSession on init and tracks session state.
///
/// ### Data Format
/// DVGs are encoded as a JSON string (array of `WatchDVGPayload`) stored under the key `"dvgs"`
/// inside the application context dictionary. This matches the format expected by the watch-side
/// `WatchConnectivityManager.processReceivedPayload(_:)`.
///
/// ### Concurrency
/// `WCSessionDelegate` methods arrive on an internal WatchConnectivity queue (nonisolated).
/// They extract `Sendable` values and dispatch to `@MainActor` using `Task { @MainActor in }`.
@MainActor
@Observable
final class WatchConnectivityService: NSObject, Sendable {

    // MARK: - Singleton

    static let shared = WatchConnectivityService()

    // MARK: - Observable State

    /// Whether WCSession has been successfully activated.
    var isActivated: Bool = false

    /// Whether a paired watch exists.
    var isPaired: Bool = false

    /// Whether the FastyDiscount watch app is installed on the paired watch.
    var isWatchAppInstalled: Bool = false

    /// Whether the watch app is currently reachable (foreground and in range).
    var isReachable: Bool = false

    /// The last error encountered during session operations, if any.
    var lastError: Error?

    // MARK: - Private

    private nonisolated let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Init

    override private init() {
        super.init()
    }

    // MARK: - Activation

    /// Activates the Watch Connectivity session.
    ///
    /// Must be called once during app startup. No-ops if WCSession is not supported
    /// (e.g., iPad without paired watch capability, or simulator).
    func activate() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivityService] WCSession not supported on this device.")
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Sync DVGs to Watch

    /// Fetches active DVGs from the repository, converts them to the watch-compatible
    /// `WatchDVGPayload` format, and sends via `updateApplicationContext`.
    ///
    /// `updateApplicationContext` replaces any previously queued context — only the
    /// latest state is delivered to the watch. This is appropriate for DVG lists where
    /// the watch only ever needs the current snapshot.
    ///
    /// - Parameter repository: The `DVGRepository` to fetch active DVGs from.
    func syncDVGsToWatch(repository: any DVGRepository) async {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default

        guard session.activationState == .activated else {
            print("[WatchConnectivityService] Cannot sync — session not activated.")
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else {
            print("[WatchConnectivityService] Cannot sync — watch not paired or app not installed.")
            return
        }

        // Fetch active DVGs from the repository
        let activeDVGs: [DVG]
        do {
            activeDVGs = try await repository.fetchActive()
        } catch {
            print("[WatchConnectivityService] Failed to fetch active DVGs: \(error)")
            lastError = error
            return
        }

        // Convert DVGs to the lightweight WatchDVGPayload format
        let payloads = activeDVGs.map { WatchDVGPayload(dvg: $0) }

        // Encode as JSON string (matches format expected by WatchConnectivityManager)
        let jsonData: Data
        do {
            jsonData = try encoder.encode(payloads)
        } catch {
            print("[WatchConnectivityService] Failed to encode DVG payloads: \(error)")
            lastError = error
            return
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[WatchConnectivityService] Failed to convert JSON data to string.")
            return
        }

        // The application context payload. Key "dvgs" is expected by the watch side.
        // Limit: ~262 KB. JSON string of DVG subset fields stays well within this.
        let context: [String: Any] = ["dvgs": jsonString]

        do {
            try session.updateApplicationContext(context)
            print("[WatchConnectivityService] Application context updated with \(payloads.count) DVG(s).")
        } catch {
            print("[WatchConnectivityService] Failed to update application context: \(error)")
            lastError = error
        }
    }

    // MARK: - Handle Incoming Mark-as-Used

    /// Handles an incoming "mark as used" action from the watch.
    ///
    /// Looks up the DVG by ID in the provided repository and marks it as used.
    /// Errors are logged but not surfaced to the user (watch-initiated actions
    /// are background operations; the next sync will reflect the corrected state).
    ///
    /// - Parameters:
    ///   - dvgID: The UUID of the DVG to mark as used.
    ///   - modelContainer: The SwiftData `ModelContainer` used to create a repository context.
    @MainActor
    private func handleMarkAsUsed(dvgID: UUID, modelContainer: ModelContainer) async {
        let context = modelContainer.mainContext
        let repository = SwiftDataDVGRepository(modelContext: context)

        do {
            let descriptor = FetchDescriptor<DVG>(
                predicate: #Predicate<DVG> { $0.id == dvgID && $0.isDeleted == false }
            )
            guard let dvg = try context.fetch(descriptor).first else {
                print("[WatchConnectivityService] markAsUsed: DVG \(dvgID) not found.")
                return
            }

            try await repository.markAsUsed(dvg)
            print("[WatchConnectivityService] markAsUsed: DVG \(dvgID) marked as used.")

            // Sync the updated state back to the watch so it reflects the change
            await syncDVGsToWatch(repository: repository)
        } catch {
            print("[WatchConnectivityService] markAsUsed: failed for DVG \(dvgID): \(error)")
            lastError = error
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let activated = activationState == .activated
        let paired = session.isPaired
        let appInstalled = session.isWatchAppInstalled
        let reachable = session.isReachable

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActivated = activated
            self.isPaired = paired
            self.isWatchAppInstalled = appInstalled
            self.isReachable = reachable

            if let error {
                self.lastError = error
                print("[WatchConnectivityService] Session activation failed: \(error)")
            } else {
                print("[WatchConnectivityService] Session activated — state: \(activationState.rawValue), paired: \(paired), watchAppInstalled: \(appInstalled).")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = false
            print("[WatchConnectivityService] Session became inactive.")
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after deactivation (happens when user switches Apple Watch)
        Task { @MainActor [weak self] in
            self?.isReachable = false
            print("[WatchConnectivityService] Session deactivated — reactivating.")
        }
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            print("[WatchConnectivityService] Reachability changed: \(reachable).")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let appInstalled = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPaired = paired
            self.isWatchAppInstalled = appInstalled
            print("[WatchConnectivityService] Watch state changed — paired: \(paired), appInstalled: \(appInstalled).")
        }
    }

    /// Handles incoming messages sent via `sendMessage` (real-time, watch is in foreground).
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        processIncomingMessage(message)
    }

    /// Handles incoming messages sent via `sendMessage` with a reply handler.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        processIncomingMessage(message)
        replyHandler(["status": "ok"])
    }

    /// Handles incoming user info sent via `transferUserInfo` (background delivery).
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        processIncomingMessage(userInfo)
    }

    // MARK: - Message Processing

    /// Extracts Sendable values from the incoming message dictionary and dispatches
    /// to MainActor for repository operations.
    ///
    /// This nonisolated helper avoids passing the non-Sendable `[String: Any]`
    /// dictionary across isolation boundaries.
    nonisolated private func processIncomingMessage(_ message: [String: Any]) {
        guard
            let action = message["action"] as? String,
            action == "markAsUsed",
            let dvgIDString = message["dvgID"] as? String,
            let dvgID = UUID(uuidString: dvgIDString)
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Retrieve the model container from the shared app environment.
            // We use a notification-based indirection so this service does not
            // need a hard dependency on the ModelContainer at construction time.
            NotificationCenter.default.post(
                name: WatchConnectivityService.markAsUsedNotification,
                object: nil,
                userInfo: ["dvgID": dvgID]
            )
        }
    }

    // MARK: - Notification Name

    /// Posted when the watch requests a "mark as used" action.
    ///
    /// The FastyDiscountApp observes this notification and calls
    /// `handleMarkAsUsedNotification(_:modelContainer:)` with the correct `ModelContainer`.
    nonisolated static let markAsUsedNotification = Notification.Name("WatchConnectivityService.markAsUsed")
}

// MARK: - App Integration Helper

extension WatchConnectivityService {

    /// Handles a "mark as used" notification posted by `processIncomingMessage`.
    ///
    /// Call this from the app's `.task` or from a `NotificationCenter` observer
    /// that has access to the `ModelContainer`.
    ///
    /// - Parameters:
    ///   - notification: The notification posted by `processIncomingMessage`.
    ///   - modelContainer: The SwiftData `ModelContainer` for repository access.
    func handleMarkAsUsedNotification(_ notification: Notification, modelContainer: ModelContainer) async {
        guard let dvgID = notification.userInfo?["dvgID"] as? UUID else { return }
        await handleMarkAsUsed(dvgID: dvgID, modelContainer: modelContainer)
    }
}

// MARK: - WatchDVGPayload

/// Lightweight Codable struct encoding the fields the Apple Watch needs from a DVG.
///
/// This mirrors `WatchDVG` on the watch side exactly, so the watch can decode
/// the JSON produced by this type directly into `[WatchDVG]`.
///
/// Fields match `WatchDVG`'s `CodingKeys` (synthesised from property names):
/// `id`, `title`, `storeName`, `code`, `barcodeType`, `dvgType`,
/// `expirationDate`, `isFavorite`, `status`.
struct WatchDVGPayload: Codable, Sendable {

    let id: UUID
    let title: String
    let storeName: String
    let code: String
    let barcodeType: String
    let dvgType: String
    let expirationDate: Date?
    let isFavorite: Bool
    let status: String

    /// Converts an iPhone `DVG` model to the lightweight watch payload.
    ///
    /// Must be called on `@MainActor` (where `DVG` is confined).
    @MainActor
    init(dvg: DVG) {
        self.id = dvg.id
        self.title = dvg.title
        self.storeName = dvg.storeName
        self.code = dvg.code
        self.barcodeType = dvg.barcodeType       // raw String, e.g. "qr"
        self.dvgType = dvg.dvgType               // raw String, e.g. "discountCode"
        self.expirationDate = dvg.expirationDate
        self.isFavorite = dvg.isFavorite
        self.status = dvg.status                 // raw String, e.g. "active"
    }
}
