import XCTest

// MARK: - OnboardingUITests
//
// Tests the onboarding flow from start to finish.
// Uses -UITestOnboarding launch argument to bypass auth without skipping onboarding.

final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Bypass auth but show onboarding (do NOT skip it)
        app.launchArguments = ["-UITestOnboarding"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test: Onboarding Flow Completes via Skip

    @MainActor
    func testOnboardingFlowCompletesViaSkip() throws {
        // Given: the onboarding screen is shown
        let skipButton = app.buttons["Skip onboarding"]
        XCTAssertTrue(
            skipButton.waitForExistence(timeout: 10),
            "Skip button should be visible on onboarding screen"
        )

        // When: tap Skip
        skipButton.tap()

        // Then: Dashboard should appear (onboarding is dismissed)
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(
            dashboardTab.waitForExistence(timeout: 10),
            "Dashboard tab should appear after skipping onboarding"
        )
    }

    // MARK: - Test: Onboarding Flow Completes via Get Started Button

    @MainActor
    func testOnboardingFlowCompletesViaGetStarted() throws {
        // Given: on the first onboarding page
        let nextButton = app.buttons["Next page"]
        XCTAssertTrue(
            nextButton.waitForExistence(timeout: 10),
            "Next button should appear on onboarding page 1"
        )

        // Navigate to page 2
        nextButton.tap()

        // Navigate to page 3
        let nextButton2 = app.buttons["Next page"]
        XCTAssertTrue(nextButton2.waitForExistence(timeout: 5))
        nextButton2.tap()

        // Wait for Get Started button (shown on last page)
        let getStartedButton = app.buttons["Get started"]
        XCTAssertTrue(
            getStartedButton.waitForExistence(timeout: 5),
            "Get Started button should appear on the last onboarding page"
        )

        // Tap Get Started
        getStartedButton.tap()

        // Dashboard should appear
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(
            dashboardTab.waitForExistence(timeout: 10),
            "Dashboard should appear after completing onboarding"
        )
    }

    // MARK: - Test: Onboarding Page Titles Are Correct

    @MainActor
    func testOnboardingPageTitlesAreCorrect() throws {
        // Given: on first onboarding page
        XCTAssertTrue(
            app.staticTexts["Never Waste a Discount Again"].waitForExistence(timeout: 10),
            "Page 1 title should be 'Never Waste a Discount Again'"
        )

        // Navigate to page 2
        let nextButton = app.buttons["Next page"]
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Everything You Need"].waitForExistence(timeout: 5),
            "Page 2 title should be 'Everything You Need'"
        )

        // Navigate to page 3
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Add Your First Discount"].waitForExistence(timeout: 5),
            "Page 3 title should be 'Add Your First Discount'"
        )
    }
}
