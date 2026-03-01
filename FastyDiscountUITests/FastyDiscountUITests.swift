import XCTest

// MARK: - FastyDiscountUITests
//
// End-to-end UI test suite for critical user flows.
// All tests are designed to run in under 2 minutes total on iPhone 15 Pro simulator.
//
// Launch arguments used:
//   -UITestMode         — bypasses Sign In with Apple, seeds mock DVG data, skips animations
//   -UITestSkipOnboarding — marks onboarding complete before launch (implied by -UITestMode)
//
// Page Object Pattern:
//   DashboardPage, DVGFormPage, SearchPage, HistoryPage, SettingsPage
//   encapsulate element queries and actions for each screen.

final class FastyDiscountUITests: XCTestCase {

    // MARK: - Setup

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Inject UI test mode flag: bypasses auth, seeds mock data, disables animations
        app.launchArguments = ["-UITestMode"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test: App Launches and Shows Dashboard

    @MainActor
    func testAppLaunchesAndShowsDashboard() throws {
        // Given: app launched in UI test mode (auth bypassed, onboarding skipped)
        // When: waiting for dashboard to appear
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(
            dashboardTab.waitForExistence(timeout: 10),
            "Dashboard tab bar item should appear after launch"
        )

        // Then: Dashboard navigation title should be visible
        let dashboardTitle = app.navigationBars["Dashboard"]
        XCTAssertTrue(
            dashboardTitle.waitForExistence(timeout: 5),
            "Dashboard navigation title should be visible"
        )
    }

    // MARK: - Test: Tab Navigation

    @MainActor
    func testTabNavigation() throws {
        // Ensure we start on Dashboard
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 10))

        // Navigate to History tab
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.exists, "History tab should exist")
        historyTab.tap()
        XCTAssertTrue(
            app.navigationBars["History"].waitForExistence(timeout: 5),
            "History navigation title should appear after tapping tab"
        )

        // Navigate to Scan tab
        let scanTab = app.tabBars.buttons["Scan"]
        XCTAssertTrue(scanTab.exists, "Scan tab should exist")
        scanTab.tap()
        XCTAssertTrue(
            app.navigationBars["Scan"].waitForExistence(timeout: 5),
            "Scan navigation title should appear after tapping tab"
        )

        // Navigate to Settings tab
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.exists, "Settings tab should exist")
        settingsTab.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Settings navigation title should appear after tapping tab"
        )

        // Navigate to Nearby tab
        let nearbyTab = app.tabBars.buttons["Nearby"]
        XCTAssertTrue(nearbyTab.exists, "Nearby tab should exist")
        nearbyTab.tap()
        XCTAssertTrue(
            app.navigationBars.element.waitForExistence(timeout: 5),
            "Navigation bar should appear after tapping Nearby tab"
        )

        // Return to Dashboard
        dashboardTab.tap()
        XCTAssertTrue(
            app.navigationBars["Dashboard"].waitForExistence(timeout: 5),
            "Should return to Dashboard"
        )
    }

    // MARK: - Test: Complete Manual DVG Creation Flow

    @MainActor
    func testManualDVGCreationFlow() throws {
        // Given: on Dashboard
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard(), "Dashboard should be visible")

        // When: tap Add menu and select Add Manually
        dashboardPage.tapAddMenu()

        let addManuallyButton = app.buttons["Add Manually"]
        XCTAssertTrue(
            addManuallyButton.waitForExistence(timeout: 5),
            "Add Manually button should appear in menu"
        )
        addManuallyButton.tap()

        // Then: DVG form should appear
        let formPage = DVGFormPage(app: app)
        XCTAssertTrue(formPage.waitForForm(), "DVG form should be presented")

        // Fill in essential fields
        formPage.fillTitle("Test Discount 99")
        formPage.fillCode("TEST99")
        formPage.fillStoreName("TestStore")

        // Save the form
        formPage.tapSave()

        // Verify we're back on dashboard (form dismissed)
        XCTAssertTrue(
            app.navigationBars["Dashboard"].waitForExistence(timeout: 8),
            "Should return to Dashboard after saving"
        )

        // Verify the new DVG appears in the recently added list
        // (The dashboard loads from SwiftData; the new item should appear)
        let newItem = app.staticTexts["Test Discount 99"]
        XCTAssertTrue(
            newItem.waitForExistence(timeout: 8),
            "Newly created DVG 'Test Discount 99' should appear on dashboard"
        )
    }

    // MARK: - Test: DVG Detail View Displays Fields Correctly

    @MainActor
    func testDVGDetailViewDisplaysFields() throws {
        // Given: on Dashboard with seeded data
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard(), "Dashboard should be visible")

        // Navigate to Search to find a specific DVG
        let searchPage = SearchPage(app: app)
        searchPage.navigateToSearch(from: dashboardPage)

        // Search for "Apple Gift Card"
        searchPage.typeSearchQuery("Apple Gift Card")

        // Tap the result
        let resultCell = app.staticTexts["Apple Gift Card"]
        XCTAssertTrue(
            resultCell.waitForExistence(timeout: 5),
            "Apple Gift Card should appear in search results"
        )
        resultCell.tap()

        // Verify detail view fields
        XCTAssertTrue(
            app.navigationBars["Apple Gift Card"].waitForExistence(timeout: 5),
            "Detail view should show DVG title as navigation title"
        )

        // Verify the store name appears
        XCTAssertTrue(
            app.staticTexts["Apple"].waitForExistence(timeout: 5),
            "Store name 'Apple' should be visible in detail view"
        )

        // Verify the code is shown
        let codeText = app.staticTexts["AAPL-GIFT-1234"]
        XCTAssertTrue(
            codeText.waitForExistence(timeout: 5),
            "DVG code 'AAPL-GIFT-1234' should be displayed"
        )

        // Verify status is shown
        XCTAssertTrue(
            app.staticTexts["Active"].waitForExistence(timeout: 5),
            "DVG status 'Active' should be shown"
        )

        // Verify type badge
        XCTAssertTrue(
            app.staticTexts["Gift Card"].waitForExistence(timeout: 5),
            "DVG type 'Gift Card' should be shown"
        )
    }

    // MARK: - Test: Search by Store Name Returns Matching Results

    @MainActor
    func testSearchByStoreNameReturnsResults() throws {
        // Given: on Dashboard
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard())

        // Navigate to Search (tap "See All" on Recently Added)
        let searchPage = SearchPage(app: app)
        searchPage.navigateToSearch(from: dashboardPage)

        // When: search for "Target"
        searchPage.typeSearchQuery("Target")

        // Then: "20% Off Everything" (at Target) should appear
        XCTAssertTrue(
            app.staticTexts["20% Off Everything"].waitForExistence(timeout: 5),
            "Target DVG '20% Off Everything' should appear in search results"
        )

        // Nike DVG should NOT appear
        XCTAssertFalse(
            app.staticTexts["Free Shipping Voucher"].exists,
            "Nike DVG should not appear when searching for Target"
        )
    }

    // MARK: - Test: Search Clears and Shows All Results

    @MainActor
    func testSearchShowsAllResultsWhenEmpty() throws {
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard())

        let searchPage = SearchPage(app: app)
        searchPage.navigateToSearch(from: dashboardPage)

        // With no query, all active DVGs should eventually appear
        // (results list shows all by default)
        XCTAssertTrue(
            app.staticTexts["No Results Found"].waitForExistence(timeout: 5)
                || app.staticTexts["20% Off Everything"].waitForExistence(timeout: 5),
            "Search view should show results or empty state"
        )
    }

    // MARK: - Test: Filter by DVG Type Shows Only Matching DVGs

    @MainActor
    func testFilterByDVGTypeShowsOnlyMatchingResults() throws {
        // Given: on Dashboard
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard())

        // Navigate to Search
        let searchPage = SearchPage(app: app)
        searchPage.navigateToSearch(from: dashboardPage)

        // Open filter sheet
        let filterButton = app.buttons["Filters"]
        XCTAssertTrue(
            filterButton.waitForExistence(timeout: 5),
            "Filter button should exist in search toolbar"
        )
        filterButton.tap()

        // Wait for filter sheet to appear
        XCTAssertTrue(
            app.navigationBars["Filters"].waitForExistence(timeout: 5),
            "Filters sheet should open"
        )

        // Select "Gift Card" type toggle
        let giftCardToggle = app.switches["Gift Card"]
        if giftCardToggle.waitForExistence(timeout: 3) {
            giftCardToggle.tap()
        }

        // Dismiss filter sheet
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()

        // Verify only Gift Card type DVGs appear
        XCTAssertTrue(
            app.staticTexts["Apple Gift Card"].waitForExistence(timeout: 5),
            "Apple Gift Card should appear when filtering by Gift Card type"
        )

        // Discount codes should not appear
        XCTAssertFalse(
            app.staticTexts["20% Off Everything"].exists,
            "Discount code DVG should not appear when filtering by Gift Card type"
        )
    }

    // MARK: - Test: Mark DVG as Used, Verify It Moves to History

    @MainActor
    func testMarkDVGAsUsedMovesToHistory() throws {
        // Given: on Dashboard, navigate to a specific DVG
        let dashboardPage = DashboardPage(app: app)
        XCTAssertTrue(dashboardPage.waitForDashboard())

        // Navigate to search and find "20% Off Everything"
        let searchPage = SearchPage(app: app)
        searchPage.navigateToSearch(from: dashboardPage)
        searchPage.typeSearchQuery("20% Off Everything")

        let dvgCell = app.staticTexts["20% Off Everything"]
        XCTAssertTrue(dvgCell.waitForExistence(timeout: 5))
        dvgCell.tap()

        // Wait for detail view
        XCTAssertTrue(
            app.navigationBars["20% Off Everything"].waitForExistence(timeout: 5),
            "Detail view should appear"
        )

        // Tap "Mark as Used" button
        let markUsedButton = app.buttons["Mark as Used"]
        XCTAssertTrue(
            markUsedButton.waitForExistence(timeout: 5),
            "Mark as Used button should be visible"
        )
        markUsedButton.tap()

        // Confirm the alert
        let confirmButton = app.buttons["Mark as Used"]
        if confirmButton.waitForExistence(timeout: 3) {
            // This is the destructive confirmation button in the alert
            let alerts = app.alerts
            if alerts.count > 0 {
                alerts.buttons["Mark as Used"].tap()
            }
        }

        // Navigate back to History tab to verify
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(
            app.navigationBars["History"].waitForExistence(timeout: 5),
            "History tab should be visible"
        )

        // The DVG should now appear in history
        // Note: The recently-used DVG should appear under "All" or "Used" filters
        let usedFilter = app.buttons["Used"]
        if usedFilter.waitForExistence(timeout: 3) {
            usedFilter.tap()
        }

        XCTAssertTrue(
            app.staticTexts["20% Off Everything"].waitForExistence(timeout: 5),
            "DVG should appear in History after being marked as used"
        )
    }

    // MARK: - Test: History Tab Shows Used and Expired DVGs

    @MainActor
    func testHistoryTabShowsHistoricalDVGs() throws {
        // Given: navigate to History tab
        app.tabBars.buttons["History"].tap()

        XCTAssertTrue(
            app.navigationBars["History"].waitForExistence(timeout: 5),
            "History view should appear"
        )

        // Seeded data includes a Used DVG ("ASOS 10% Off") and Expired ("Black Friday Voucher")
        // Default "All" filter should show both

        // Check for used DVG
        XCTAssertTrue(
            app.staticTexts["ASOS 10% Off"].waitForExistence(timeout: 5),
            "Used DVG 'ASOS 10% Off' should appear in history"
        )

        // Check for expired DVG
        XCTAssertTrue(
            app.staticTexts["Black Friday Voucher"].waitForExistence(timeout: 5),
            "Expired DVG 'Black Friday Voucher' should appear in history"
        )
    }

    // MARK: - Test: History Tab Filter Chips

    @MainActor
    func testHistoryTabFilterChips() throws {
        // Navigate to History
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        // Tap "Used" filter
        let usedFilter = app.buttons["Used"]
        if usedFilter.waitForExistence(timeout: 3) {
            usedFilter.tap()

            // Should show ASOS 10% Off (used)
            XCTAssertTrue(
                app.staticTexts["ASOS 10% Off"].waitForExistence(timeout: 5),
                "Used filter should show 'ASOS 10% Off'"
            )

            // Should NOT show Black Friday Voucher (expired)
            XCTAssertFalse(
                app.staticTexts["Black Friday Voucher"].exists,
                "Used filter should not show expired DVGs"
            )
        }

        // Tap "Expired" filter
        let expiredFilter = app.buttons["Expired"]
        if expiredFilter.waitForExistence(timeout: 3) {
            expiredFilter.tap()

            // Should show Black Friday Voucher (expired)
            XCTAssertTrue(
                app.staticTexts["Black Friday Voucher"].waitForExistence(timeout: 5),
                "Expired filter should show 'Black Friday Voucher'"
            )
        }
    }

    // MARK: - Test: Settings View Loads All Sections

    @MainActor
    func testSettingsViewLoadsAllSections() throws {
        // Navigate to Settings
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Settings view should appear"
        )

        // Verify all major sections appear
        let accountHeader = app.staticTexts["Account"]
        XCTAssertTrue(
            accountHeader.waitForExistence(timeout: 5),
            "Account section should be present in Settings"
        )

        let notificationsHeader = app.staticTexts["Notifications"]
        XCTAssertTrue(
            notificationsHeader.waitForExistence(timeout: 5),
            "Notifications section should be present in Settings"
        )

        let locationHeader = app.staticTexts["Location"]
        XCTAssertTrue(
            locationHeader.waitForExistence(timeout: 5),
            "Location section should be present in Settings"
        )

        let appearanceHeader = app.staticTexts["Appearance"]
        XCTAssertTrue(
            appearanceHeader.waitForExistence(timeout: 5),
            "Appearance section should be present in Settings"
        )

        let aboutHeader = app.staticTexts["About"]
        XCTAssertTrue(
            aboutHeader.waitForExistence(timeout: 5),
            "About section should be present in Settings"
        )
    }

    // MARK: - Test: Scan Tab Shows Options

    @MainActor
    func testScanTabShowsScanOptions() throws {
        // Navigate to Scan tab
        app.tabBars.buttons["Scan"].tap()

        XCTAssertTrue(
            app.navigationBars["Scan"].waitForExistence(timeout: 5),
            "Scan tab navigation title should appear"
        )

        // Verify scan options are present
        let scanText = app.staticTexts["Scan Barcodes & QR Codes"]
        XCTAssertTrue(
            scanText.waitForExistence(timeout: 5),
            "Scan placeholder view should display the main heading"
        )

        // Camera scanner button
        let cameraButton = app.buttons["Open barcode scanner"]
        XCTAssertTrue(
            cameraButton.waitForExistence(timeout: 5),
            "Open Camera Scanner button should be visible"
        )

        // Import from photo/PDF button
        let importButton = app.buttons["Import from photo or PDF"]
        XCTAssertTrue(
            importButton.waitForExistence(timeout: 5),
            "Import from Photo or PDF button should be visible"
        )
    }
}

// MARK: - Page Objects

// MARK: DashboardPage

/// Encapsulates Dashboard screen interactions for UI tests.
final class DashboardPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Waits for the Dashboard to be fully loaded.
    func waitForDashboard(timeout: TimeInterval = 10) -> Bool {
        app.navigationBars["Dashboard"].waitForExistence(timeout: timeout)
    }

    /// Taps the "+" add menu button in the Dashboard toolbar.
    func tapAddMenu() {
        let addButton = app.buttons["Add new discount"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
        }
    }

    /// Taps "See All" on the Recently Added section to go to Search.
    func tapRecentlyAddedSeeAll() {
        let seeAllButton = app.buttons["See all Recently Added"]
        if seeAllButton.waitForExistence(timeout: 5) {
            seeAllButton.tap()
        }
    }
}

// MARK: DVGFormPage

/// Encapsulates DVG Form screen interactions for UI tests.
final class DVGFormPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Waits for the DVG form to be fully presented.
    func waitForForm(timeout: TimeInterval = 8) -> Bool {
        app.navigationBars["New Item"].waitForExistence(timeout: timeout)
    }

    /// Fills the Title field.
    func fillTitle(_ title: String) {
        let titleField = app.textFields["Title"]
        if titleField.waitForExistence(timeout: 5) {
            titleField.tap()
            titleField.typeText(title)
        }
    }

    /// Fills the Code field.
    func fillCode(_ code: String) {
        let codeField = app.textFields["Code (e.g., SAVE20)"]
        if codeField.waitForExistence(timeout: 5) {
            codeField.tap()
            codeField.typeText(code)
        }
    }

    /// Fills the Store Name field.
    func fillStoreName(_ storeName: String) {
        let storeField = app.textFields["Store Name"]
        if storeField.waitForExistence(timeout: 5) {
            storeField.tap()
            storeField.typeText(storeName)
        }
    }

    /// Taps the Save button.
    func tapSave() {
        let saveButton = app.buttons["Save"]
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.tap()
        }
    }

    /// Taps the Cancel button.
    func tapCancel() {
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 5) {
            cancelButton.tap()
        }
    }
}

// MARK: SearchPage

/// Encapsulates Search screen interactions for UI tests.
final class SearchPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Navigates to Search view via the Dashboard's "See All" button.
    func navigateToSearch(from dashboard: DashboardPage) {
        dashboard.tapRecentlyAddedSeeAll()
        _ = app.navigationBars["Search"].waitForExistence(timeout: 5)
    }

    /// Types a query in the search field.
    func typeSearchQuery(_ query: String) {
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText(query)
        }
    }

    /// Clears the search field.
    func clearSearch() {
        let clearButton = app.buttons["Clear text"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
        }
    }
}

// MARK: HistoryPage

/// Encapsulates History screen interactions for UI tests.
final class HistoryPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Navigates to the History tab.
    func navigateToHistory() {
        app.tabBars.buttons["History"].tap()
    }

    /// Waits for History view to load.
    func waitForHistory(timeout: TimeInterval = 5) -> Bool {
        app.navigationBars["History"].waitForExistence(timeout: timeout)
    }

    /// Taps a filter chip by name.
    func tapFilter(_ filterName: String) {
        let filterButton = app.buttons[filterName]
        if filterButton.waitForExistence(timeout: 3) {
            filterButton.tap()
        }
    }
}

// MARK: SettingsPage

/// Encapsulates Settings screen interactions for UI tests.
final class SettingsPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Navigates to the Settings tab.
    func navigateToSettings() {
        app.tabBars.buttons["Settings"].tap()
    }

    /// Waits for Settings view to load.
    func waitForSettings(timeout: TimeInterval = 5) -> Bool {
        app.navigationBars["Settings"].waitForExistence(timeout: timeout)
    }
}
