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
        app.launchArguments = ["-UITestSkipOnboarding", "-UITestResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-UITestSkipOnboarding", "-UITestResetData", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["债务"].exists)
        XCTAssertTrue(app.tabBars.buttons["流水"].exists)
        XCTAssertTrue(app.tabBars.buttons["策略"].exists)
        XCTAssertTrue(app.tabBars.buttons["统计"].exists)
    }

    @MainActor
    func testFortyDebtRealisticUserJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipOnboarding",
            "-UITestResetData",
            "-UITestSeedFortyDebtScenario",
            "-UITestFullAccess",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Total remaining"].waitForExistence(timeout: 10))

        let addMenuButton = app.buttons["Add"].firstMatch
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 5))
        addMenuButton.tap()
        XCTAssertTrue(app.menuItems["Add Debt"].waitForExistence(timeout: 5) || app.buttons["Add Debt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Record Payment"].exists || app.buttons["Record Payment"].exists)
        XCTAssertTrue(app.menuItems["Add Manual Overdue"].exists || app.buttons["Add Manual Overdue"].exists)

        (app.menuItems["Add Manual Overdue"].firstMatch.exists ? app.menuItems["Add Manual Overdue"].firstMatch : app.buttons["Add Manual Overdue"].firstMatch).tap()
        XCTAssertTrue(app.navigationBars["Add Manual Overdue"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        app.tabBars.buttons["Debts"].tap()
        let cardRow = scrollToStaticText("CC-04 Fuel Card", in: app)
        XCTAssertTrue(cardRow.exists)

        cardRow.tap()
        XCTAssertTrue(app.staticTexts["Card Info"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record Payment"].firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Payments"].tap()
        XCTAssertTrue(app.staticTexts["Recent Payments"].waitForExistence(timeout: 5))

        app.buttons["Record Payment"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Record Payment"].waitForExistence(timeout: 5))
        let paymentDateButton = app.buttons["Payment Date"].firstMatch.exists
            ? app.buttons["Payment Date"].firstMatch
            : app.descendants(matching: .any)["Payment date"].firstMatch
        if paymentDateButton.waitForExistence(timeout: 5) {
            paymentDateButton.tap()
            if app.datePickers.firstMatch.waitForExistence(timeout: 2)
                || app.pickerWheels.firstMatch.waitForExistence(timeout: 2) {
                let doneButton = app.buttons["common.done"].firstMatch.exists
                    ? app.buttons["common.done"].firstMatch
                    : app.buttons["Done"].firstMatch
                if doneButton.waitForExistence(timeout: 2) {
                    doneButton.tap()
                }
            }
        }

        let amountField = app.textFields["Amount"].firstMatch
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()
        amountField.typeText("25")
        app.buttons["Save"].firstMatch.tap()
        dismissResultAlertIfPresent(in: app)

        app.tabBars.buttons["Payments"].tap()
        XCTAssertTrue(app.staticTexts["Recent Payments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$25.00"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Strategy"].tap()
        XCTAssertTrue(app.staticTexts["Generate Strategy"].waitForExistence(timeout: 5))
        app.buttons["Generate Strategy"].firstMatch.tap()
        dismissResultAlertIfPresent(in: app)
        XCTAssertTrue(app.staticTexts["Latest Result"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["History"].exists)

        app.tabBars.buttons["Statistics"].tap()
        XCTAssertTrue(
            app.otherElements["statistics.debt.card"].firstMatch.waitForExistence(timeout: 8)
                || app.staticTexts["Debt Statistics"].firstMatch.waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.otherElements["statistics.payment.card"].firstMatch.exists
                || app.staticTexts["Payment Statistics"].firstMatch.exists
        )
        XCTAssertTrue(
            app.otherElements["statistics.overdue.card"].firstMatch.exists
                || app.staticTexts["Overdue Statistics"].firstMatch.exists
        )
        XCTAssertTrue(
            app.otherElements["statistics.summary.card"].firstMatch.exists
                || app.staticTexts["Summary"].firstMatch.exists
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestSkipOnboarding", "-UITestResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
        }
    }

    @MainActor
    private func dismissResultAlertIfPresent(in app: XCUIApplication) {
        let errorAlert = app.alerts["Could not complete action"]
        if errorAlert.waitForExistence(timeout: 1) {
            XCTFail("Unexpected error alert while saving")
            return
        }

        let savedAlert = app.alerts["Saved"]
        if savedAlert.waitForExistence(timeout: 3) {
            savedAlert.buttons.firstMatch.tap()
        }
    }

    @MainActor
    private func scrollToStaticText(_ label: String, in app: XCUIApplication, maxSwipes: Int = 10) -> XCUIElement {
        let element = app.staticTexts[label]
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return element
            }
            app.swipeUp()
        }
        return element
    }

}
