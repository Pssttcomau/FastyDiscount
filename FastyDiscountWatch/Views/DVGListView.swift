import SwiftUI

// MARK: - DVGListViewModel

/// View model for the DVG list on Apple Watch.
///
/// Loads active DVGs from the local cache and listens for updates
/// from Watch Connectivity.
@Observable
@MainActor
final class DVGListViewModel {

    // MARK: - State

    var dvgs: [WatchDVG] = []
    var isLoading = false

    // MARK: - Init

    init() {}

    // MARK: - Data Loading

    /// Loads active DVGs from the local store.
    func loadDVGs() {
        isLoading = true
        dvgs = WatchDVGStore.shared.loadActiveDVGs()
        isLoading = false
    }

    /// Sets up a callback to reload when new DVGs arrive from the iPhone.
    func startListening() {
        WatchConnectivityManager.shared.onDVGsReceived = { @MainActor [weak self] _ in
            self?.loadDVGs()
        }
    }
}

// MARK: - DVGListView

/// Scrollable list of active DVGs on the Apple Watch.
///
/// Shows DVGs sorted by expiry date (soonest first), with each row displaying
/// the title, store name, expiry badge, and type icon. Tapping a DVG opens
/// the full-screen barcode view.
struct DVGListView: View {

    @State private var viewModel = DVGListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.dvgs.isEmpty && !viewModel.isLoading {
                    WatchEmptyStateView()
                } else {
                    dvgList
                }
            }
            .navigationTitle("Discounts")
            .task {
                viewModel.startListening()
                viewModel.loadDVGs()
            }
        }
    }

    // MARK: - Subviews

    private var dvgList: some View {
        List {
            ForEach(viewModel.dvgs) { dvg in
                NavigationLink(value: dvg) {
                    DVGRowView(dvg: dvg)
                }
            }
        }
        .listStyle(.carousel)
        .navigationDestination(for: WatchDVG.self) { dvg in
            DVGBarcodeView(dvg: dvg)
        }
    }
}

// MARK: - Preview

#Preview {
    DVGListView()
}
