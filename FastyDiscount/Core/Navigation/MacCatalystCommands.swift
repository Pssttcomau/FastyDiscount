import SwiftUI
import UniformTypeIdentifiers

// MARK: - MacCatalystCommands

/// Menu bar commands for the Mac Catalyst build.
///
/// Provides File, Edit, and View menus with keyboard shortcuts.
/// Only compiled and available when running as a Mac Catalyst app.
///
/// Usage: attach `.commands { MacCatalystCommands(router: router) }` to
/// the `WindowGroup` in `FastyDiscountApp`.
struct MacCatalystCommands: Commands {

    // MARK: - Action Callbacks

    /// Called when the user selects File > New DVG.
    let onNewDVG: () -> Void
    /// Called when the user selects File > Import from Photo.
    let onImportPhoto: () -> Void
    /// Called when the user selects File > Import PDF.
    let onImportPDF: () -> Void
    /// Called when the user selects View > Show Dashboard.
    let onShowDashboard: () -> Void
    /// Called when the user selects View > Show History.
    let onShowHistory: () -> Void
    /// Called when the user selects View > Show Settings.
    let onShowSettings: () -> Void
    /// Called when the user selects Edit > Search (Cmd+F).
    let onSearch: () -> Void

    // MARK: - Body

    var body: some Commands {
        fileMenu
        editSearchCommand
        viewMenu
    }

    // MARK: - File Menu

    @CommandsBuilder
    private var fileMenu: some Commands {
        CommandMenu("File") {
            Button("New DVG") {
                onNewDVG()
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Create a new discount, voucher, or gift card")

            Divider()

            Button("Import from Photo...") {
                onImportPhoto()
            }
            .keyboardShortcut("i", modifiers: .command)
            .accessibilityLabel("Import a discount from a photo")

            Button("Import PDF...") {
                onImportPDF()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .accessibilityLabel("Import a discount from a PDF document")
        }
    }

    // MARK: - Edit Menu (Search command added to existing Edit menu)

    @CommandsBuilder
    private var editSearchCommand: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Search") {
                onSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Search discounts, vouchers, and gift cards")
        }
    }

    // MARK: - View Menu

    @CommandsBuilder
    private var viewMenu: some Commands {
        CommandMenu("View") {
            Button("Show Dashboard") {
                onShowDashboard()
            }
            .keyboardShortcut("1", modifiers: .command)
            .accessibilityLabel("Switch to the Dashboard view")

            Button("Show History") {
                onShowHistory()
            }
            .keyboardShortcut("2", modifiers: .command)
            .accessibilityLabel("Switch to the History view")

            Divider()

            Button("Settings...") {
                onShowSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")
        }
    }
}

// MARK: - DeleteKeyboardShortcut

/// A transparent overlay view that captures the Delete key and triggers
/// a callback. Attach it to list rows that support deletion on Mac.
///
/// Usage:
/// ```swift
/// myRowView
///     .background(DeleteKeyboardShortcut { deleteSelectedItem() })
/// ```
struct DeleteKeyboardShortcutView: View {
    let onDelete: () -> Void

    var body: some View {
        Button("Delete", role: .destructive, action: onDelete)
            .keyboardShortcut(.delete, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
