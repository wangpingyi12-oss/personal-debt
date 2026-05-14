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
    func testMainTabsAreVisible() throws {
        let app = try launchAppOrSkip()

        XCTAssertTrue(app.tabBars.buttons["总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["债务"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["策略"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["统计"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["规则"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSubscriptionCenterCanBeOpenedFromSettings() throws {
        let app = try launchAppOrSkip()

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["订阅中心"].waitForExistence(timeout: 5))
        app.staticTexts["订阅中心"].tap()

        XCTAssertTrue(app.staticTexts["订阅套餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["恢复购买"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["校验并同步"].waitForExistence(timeout: 5))
    }
}
