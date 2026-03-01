import Foundation

// MARK: - WatchDVGStore

/// Manages local JSON-based storage of DVGs on the Apple Watch.
///
/// DVGs are stored as a JSON array in the watch's local documents directory.
/// This provides offline access to synced DVGs without requiring a SwiftData container.
///
/// Thread-safe via `@MainActor` isolation since all reads and writes happen
/// in response to UI or Watch Connectivity events.
@MainActor
final class WatchDVGStore: Sendable {

    // MARK: - Singleton

    static let shared = WatchDVGStore()

    // MARK: - Storage

    /// The file URL for the local DVG cache.
    private var cacheFileURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("watch_dvgs.json")
    }

    // MARK: - JSON Encoder/Decoder

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Loads all cached DVGs from local storage.
    /// Returns an empty array if no cache exists or the file cannot be read.
    func loadDVGs() -> [WatchDVG] {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let dvgs = try decoder.decode([WatchDVG].self, from: data)
            return dvgs
        } catch {
            // Corrupted cache -- return empty and let next sync rebuild it
            return []
        }
    }

    /// Saves the given DVGs to local storage, replacing any existing cache.
    func saveDVGs(_ dvgs: [WatchDVG]) {
        do {
            let data = try encoder.encode(dvgs)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            // Silently fail -- the cache is non-critical and will be rebuilt on next sync
        }
    }

    /// Returns only the active (non-expired, non-used) DVGs, sorted by
    /// expiry date (soonest first), then by favorite status (favorites first).
    func loadActiveDVGs() -> [WatchDVG] {
        let allDVGs = loadDVGs()
        return allDVGs
            .filter { $0.isActive }
            .sorted { lhs, rhs in
                // Primary sort: expiry date ascending (soonest first)
                // DVGs without expiry go to the end
                let lhsDate = lhs.expirationDate ?? Date.distantFuture
                let rhsDate = rhs.expirationDate ?? Date.distantFuture

                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }

                // Secondary sort: favorites first
                if lhs.isFavorite != rhs.isFavorite {
                    return lhs.isFavorite
                }

                // Tertiary sort: alphabetical by title
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// Updates the status of a single DVG by ID.
    /// Used when marking a DVG as used from the watch.
    func updateStatus(for dvgID: UUID, to newStatus: WatchDVGStatus) {
        var dvgs = loadDVGs()
        guard let index = dvgs.firstIndex(where: { $0.id == dvgID }) else { return }

        let existing = dvgs[index]
        dvgs[index] = WatchDVG(
            id: existing.id,
            title: existing.title,
            storeName: existing.storeName,
            code: existing.code,
            barcodeType: existing.barcodeType,
            dvgType: existing.dvgType,
            expirationDate: existing.expirationDate,
            isFavorite: existing.isFavorite,
            status: newStatus.rawValue
        )

        saveDVGs(dvgs)
    }

    /// Returns the next DVG to expire (for complications).
    /// Only considers active DVGs with an expiration date.
    func nextExpiringDVG() -> WatchDVG? {
        loadActiveDVGs().first { $0.expirationDate != nil }
    }

    /// Removes all cached data.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}
