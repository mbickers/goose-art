import XCTest

final class EmojiDragTests: XCTestCase {
    @MainActor
    func testDragRecentEmojiToCanvas() {
        let app = openCanvas()
        let placement = app.staticTexts["placement-🦆"]
        let count = app.staticTexts.matching(identifier: "placement-🦆").count
        app.staticTexts["recent-🦆"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            )
        XCTAssertTrue(placement.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts.matching(identifier: "placement-🦆").count, count + 1)
        let position = placement.frame.origin
        placement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35))
        )
        XCTAssertEqual(app.staticTexts.matching(identifier: "placement-🦆").count, count + 1)
        XCTAssertNotEqual(placement.frame.origin, position)
    }

    @MainActor
    func testDragKeyboardEmojiToCanvas() {
        let app = openCanvas()
        app.textFields["emoji-picker"].tap()
        let emoji = app.keys["😂"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 3))
        let count = app.staticTexts.matching(identifier: "placement-😂").count
        emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        )
        let placementExists = app.staticTexts["placement-😂"].waitForExistence(timeout: 5)
        let image = app.screenshot()
        let screenshot = XCTAttachment(screenshot: image)
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(placementExists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "placement-😂").count, count + 1)
    }

    @MainActor
    private func openCanvas() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["recent-🦆"].waitForExistence(timeout: 3))
        return app
    }
}
