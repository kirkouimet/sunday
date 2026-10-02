import XCTest

/// Walks every main screen with sample data and saves screenshots, so design
/// reviews can look at the real app. Set SCREENSHOT_DIR to write PNGs to disk;
/// they are also attached to the test result either way.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testLightMode() { captureAll(variant: "light") }

    func testDarkMode() { captureAll(variant: "dark", arguments: ["-uiDarkMode"]) }

    func testLargeText() {
        captureAll(variant: "ax-large",
                   arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    private func captureAll(variant: String, arguments: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()

        let card = app.buttons.matching(identifier: "mealCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Feed never showed a dinner")
        snap("1-feed", variant)

        app.swipeUp()
        snap("2-feed-scrolled", variant)
        app.swipeDown()
        app.swipeDown()

        card.tap()
        sleep(1)
        snap("3-detail", variant)
        app.swipeUp()
        snap("4-detail-history", variant)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Add dinner"].firstMatch.tap()
        sleep(1)
        snap("5-new-dinner", variant)
        let nameField = app.textFields["Name this dinner"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Lem")
            snap("6-new-dinner-typing", variant)
        }
        app.buttons["Cancel"].firstMatch.tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }

        app.tabBars.buttons["Ideas"].tap()
        sleep(1)
        snap("7-ideas", variant)

        app.tabBars.buttons["Family"].tap()
        sleep(1)
        snap("8-family", variant)
    }

    private func snap(_ name: String, _ variant: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(variant)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(variant)-\(name).png")
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
