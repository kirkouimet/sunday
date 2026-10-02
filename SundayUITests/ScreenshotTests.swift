import XCTest

/// Walks every main screen with sample data and attaches screenshots to the
/// test result, so design reviews can look at the real app. CI exports them.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testLightMode() { captureAll(variant: "light") }

    func testDarkMode() { captureAll(variant: "dark", arguments: ["-uiDarkMode"]) }

    func testLargeText() {
        captureAll(variant: "axlarge",
                   arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    private func captureAll(variant: String, arguments: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()

        let card = app.buttons["heroCard"].firstMatch
        guard card.waitForExistence(timeout: 15) else {
            snap("0-launch-failed", variant)
            XCTFail("Feed never showed a dinner")
            return
        }
        snap("1-feed", variant)

        // Detail first, while the hero card is on screen and nothing is
        // scrolling (a tap during scroll momentum just stops the scroll).
        card.tap()
        if !app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 4) {
            card.tap()
        }
        sleep(1)
        snap("3-detail", variant)
        app.swipeUp()
        sleep(1)
        snap("4-detail-history", variant)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        sleep(1)

        app.swipeUp()
        sleep(1)
        snap("2-feed-scrolled", variant)
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        // New dinner
        let add = app.buttons["addDinner"].firstMatch
        if add.waitForExistence(timeout: 5) {
            add.tap()
            sleep(1)
            snap("5-new-dinner", variant)
            // Sample data already has a dinner that day; choose a new one to reach the form.
            let different = app.buttons["Different dinner"].firstMatch
            if different.waitForExistence(timeout: 2) { different.tap() }
            let nameField = app.textFields.firstMatch
            if nameField.waitForExistence(timeout: 3) {
                nameField.tap()
                nameField.typeText("Lem")
                sleep(1)
                snap("6-new-dinner-typing", variant)
            }
            app.buttons["Cancel"].firstMatch.tap()
            let discard = app.buttons["Discard"].firstMatch
            if discard.waitForExistence(timeout: 4) { discard.tap() }
            // At large text sizes the sheet takes a moment to go away.
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 6)
        } else {
            XCTFail("No add button")
        }

        tapTab(app, "Ideas")
        snap("7-ideas", variant)

        tapTab(app, "Family")
        snap("8-family", variant)
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        if !tab.waitForExistence(timeout: 4) {
            // iOS 26 minimizes the tab bar after scrolling; scroll back up to expand it.
            app.swipeDown()
            app.swipeDown()
        }
        if tab.waitForExistence(timeout: 4) {
            tab.tap()
        } else if app.buttons[name].firstMatch.exists {
            app.buttons[name].firstMatch.tap()
        } else {
            // Last resort: the minimized tab bar's selected item, then the target.
            app.tabBars.buttons.element(boundBy: 0).tap()
            if tab.waitForExistence(timeout: 3) { tab.tap() }
        }
        sleep(1)
    }

    private func snap(_ name: String, _ variant: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(variant)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
