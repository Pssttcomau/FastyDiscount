import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityManager

/// Manages Watch Connectivity communication between the watch and the paired iPhone.
///
/// Currently provides stubbed implementations for:
/// - Receiving DVG data from the iPhone (via `updateApplicationContext` or `transferUserInfo`)
/// - Sending "mark as used" actions back to the iPhone (via `sendMessage`)
///
/// Full sync implementation will be completed in TASK-035.
@MainActor
final class WatchConnectivityManager: NSObject, Sendable {

    // MARK: - Singleton

    static let shared = WatchConnectivityManager()

    // MARK: - Callbacks

    /// Called when new DVG data is received from the iPhone.
    var onDVGsReceived: (@MainActor @Sendable ([WatchDVG]) -> Void)?

    // MARK: - Properties

    private nonisolated let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    override private init() {
        super.init()
    }

    // MARK: - Activation

    /// Activates the Watch Connectivity session.
    /// Call this once during app launch.
    func activate() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Send Actions

    /// Sends a "mark as used" action to the iPhone for the given DVG ID.
    ///
    /// This uses `sendMessage` for immediate delivery when the iPhone app is reachable,
    /// falling back to `transferUserInfo` for background delivery.
    ///
    /// - Parameter dvgID: The UUID of the DVG to mark as used.
    nonisolated func sendMarkAsUsed(dvgID: UUID) {
        let idString = dvgID.uuidString

        let message: [String: Any] = [
            "action": "markAsUsed",
            "dvgID": idString
        ]

        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                // Fallback to transferUserInfo if sendMessage fails
                WCSession.default.transferUserInfo(message)
            }
        } else {
            // iPhone not reachable -- queue for delivery when available
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - Process Received Data

    /// Extracts DVG JSON string from received dictionary on the calling thread,
    /// then decodes and saves on the main actor.
    /// This avoids sending non-Sendable `[String: Any]` across isolation boundaries.
    nonisolated private func processReceivedPayload(_ payload: [String: Any]) {
        // Extract the Sendable string value on the current (nonisolated) thread
        guard let dvgDataString = payload["dvgs"] as? String,
              let dvgData = dvgDataString.data(using: .utf8) else {
            return
        }

        // Decode on the current thread (no isolation needed for pure decoding)
        let dvgs: [WatchDVG]
        do {
            dvgs = try decoder.decode([WatchDVG].self, from: dvgData)
        } catch {
            // Failed to decode DVG data -- ignore and wait for next sync
            return
        }

        // Now pass the Sendable [WatchDVG] to the MainActor
        Task { @MainActor [dvgs] in
            WatchDVGStore.shared.saveDVGs(dvgs)
            self.onDVGsReceived?(dvgs)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Session activated -- ready for communication
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        processReceivedPayload(applicationContext)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        processReceivedPayload(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        processReceivedPayload(message)
    }
}
