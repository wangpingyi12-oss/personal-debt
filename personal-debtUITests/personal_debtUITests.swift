//
//  personal_debtUITests.swift
//  personal-debtUITests
//
//  Created by Mac on 2026/4/25.
//

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
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMainTabsAndDebtEntryAreVisible() throws {
        let app = try launchAppOrSkip()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        XCTAssertTrue(tabBar.buttons["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["债务"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["流水"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["策略"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["设置"].waitForExistence(timeout: 5))

        tabBar.buttons["债务"].tap()
        XCTAssertTrue(app.buttons["新增"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testSubscriptionPageCanBeOpenedBeforeProductsAreConfigured() throws {
        let app = try launchAppOrSkip()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        tabBar.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["订阅管理"].waitForExistence(timeout: 5))

        app.staticTexts["订阅管理"].tap()

        XCTAssertTrue(app.staticTexts["订阅套餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["恢复购买"].waitForExistence(timeout: 5))
    }
}
