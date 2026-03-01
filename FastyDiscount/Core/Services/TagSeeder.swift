import Foundation
import SwiftData

// MARK: - TagSeeder

/// Seeds the system-defined `Tag` records into the SwiftData store on first
/// launch and on subsequent launches whenever new system tags have been added.
///
/// The seeder is **idempotent**: it checks whether each system tag already
/// exists before inserting, so calling it multiple times is safe and produces
/// no duplicates.
///
/// ### Usage
/// Call `TagSeeder.seedIfNeeded(in:)` from the app's startup sequence,
/// typically inside the `@main` App struct or a scene `onAppear` handler:
///
/// ```swift
/// .task {
///     await TagSeeder.seedIfNeeded(in: modelContext)
/// }
/// ```
@MainActor
enum TagSeeder {

    // MARK: - Public API

    /// Inserts any missing system tags into `context`.
    ///
    /// - Parameter context: The `ModelContext` to query and insert into.
    ///   Must be called on the `@MainActor`.
    static func seedIfNeeded(in context: ModelContext) {
        let existingNames = fetchExistingSystemTagNames(in: context)

        var inserted = 0
        for systemTag in SystemTag.allCases {
            guard !existingNames.contains(systemTag.rawValue) else { continue }
            let tag = Tag(systemTag: systemTag)
            context.insert(tag)
            inserted += 1
        }

        if inserted > 0 {
            do {
                try context.save()
            } catch {
                // Non-fatal: tags will be re-attempted on next launch.
                print("[TagSeeder] Failed to save seeded tags: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns the names of all system tags that already exist in the store.
    private static func fetchExistingSystemTagNames(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.isSystemTag == true && $0.isDeleted == false }
        )

        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.map { $0.name })
    }
}
