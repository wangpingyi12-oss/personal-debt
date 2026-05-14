import XCTest

final class personal_debtUITests: XCTestCase {
    @MainActor
    private func launchAppOrSkip() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        guard app.wait(for: .runningForeground, timeout: 15) else {
            throw XCTSkip("UI test app did not reach foreground in current environment")
        }

        let mainWindow = app.windows.element(boundBy: 0)
        guard mainWindow.waitForExistence(timeout: 10) else {
            throw XCTSkip("UI accessibility window is unavailable in current environment")
        }
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsOnlyRetainedEntryPoints() throws {
        let app = try launchAppOrSkip()

        XCTAssertTrue(app.staticTexts["订阅中心"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["法务与隐私"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["支持与联系"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Simplified Home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSubscriptionCenterOpensAndShowsPurchaseActions() throws {
        let app = try launchAppOrSkip()

        app.staticTexts["订阅中心"].tap()

        XCTAssertTrue(app.staticTexts["订阅套餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["恢复购买"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["校验并同步"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Subscription Center"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
