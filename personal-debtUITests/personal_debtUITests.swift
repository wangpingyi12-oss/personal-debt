//
//  personal_debtUITests.swift
//  personal-debtUITests
//
//  Created by Mac on 2026/5/14.
//

import XCTest

final class personal_debtUITests: XCTestCase {

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
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipOnboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Debts"].exists)
        XCTAssertTrue(app.tabBars.buttons["Payments"].exists)
        XCTAssertTrue(app.tabBars.buttons["Strategy"].exists)
        XCTAssertTrue(app.tabBars.buttons["Statistics"].exists)
    }

    @MainActor
    func testChineseLocalizationLaunchesDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipOnboarding", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["债务"].exists)
        XCTAssertTrue(app.tabBars.buttons["流水"].exists)
        XCTAssertTrue(app.tabBars.buttons["策略"].exists)
        XCTAssertTrue(app.tabBars.buttons["统计"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestSkipOnboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
        }
    }
}
