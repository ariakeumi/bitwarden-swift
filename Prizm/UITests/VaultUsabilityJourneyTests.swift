import XCTest

final class VaultUsabilityJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test-vault", "--ui-test-note", "-AppleLanguages", "(en)",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 20))
        XCTAssertTrue(element("itemList.row.alpha").waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private var columnDividers: [XCUIElement] {
        app.splitters.allElementsBoundByIndex
            .filter { $0.frame.height > 200 && $0.frame.width < 20 }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    func testSortSharesNativeToolbarWithAddAndKeepsItsSelection() {
        let addButton = element("create.button.newItem")
        let sortButton = element("itemList.sortMenu")
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.toolbars.descendants(matching: .any)["itemList.sortMenu"].firstMatch.exists)
        XCTAssertEqual(sortButton.frame.midY, addButton.frame.midY, accuracy: 1)
        XCTAssertEqual(sortButton.frame.height, addButton.frame.height, accuracy: 1)
        XCTAssertGreaterThan(sortButton.frame.minX, addButton.frame.minX)
        XCTAssertLessThan(sortButton.frame.minX - addButton.frame.maxX, 24)

        let toolbarScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        toolbarScreenshot.name = "Native Add and Sort Toolbar"
        toolbarScreenshot.lifetime = .keepAlways
        add(toolbarScreenshot)

        sortButton.click()
        let descending = app.menuItems["Name (Z–A)"]
        XCTAssertTrue(descending.waitForExistence(timeout: 3))
        descending.click()
        XCTAssertGreaterThan(element("itemList.row.alpha").frame.minY, element("itemList.row.note").frame.minY)

        app.terminate()
        app.launch()
        XCTAssertTrue(element("itemList.row.alpha").waitForExistence(timeout: 20))
        XCTAssertGreaterThan(element("itemList.row.alpha").frame.minY, element("itemList.row.note").frame.minY)
        element("itemList.sortMenu").click()
        app.menuItems["Name (A–Z)"].click()
        XCTAssertLessThan(element("itemList.row.alpha").frame.minY, element("itemList.row.note").frame.minY)

        element("create.button.newItem").click()
        XCTAssertTrue(app.menuItems["Login"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testArrowKeysNavigateImmediatelyAfterLaunch() {
        app.activate()
        app.typeKey(.downArrow, modifierFlags: [])
        let name = element("detail.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Alpha Bank")

        app.typeKey(.downArrow, modifierFlags: [])
        let nextItem = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Beta Mail"), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [nextItem], timeout: 5), .completed)
        XCTAssertEqual(name.value as? String, "Beta Mail")
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertEqual(name.value as? String, "Alpha Bank")
    }

    func testCommandClickSelectsMultipleItemsAndReturnsToSingleDetail() {
        let alpha = element("itemList.row.alpha")
        let beta = element("itemList.row.beta")
        alpha.click()
        XCUIElement.perform(withKeyModifiers: .command) { beta.click() }

        let summary = element("itemList.selectionSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "2 items selected")
        XCTAssertFalse(element("detail.name").exists)
        app.menuBars.menuBarItems["Item"].click()
        XCTAssertFalse(app.menuItems["Edit"].isEnabled)
        XCTAssertFalse(app.menuItems["Copy Password"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        XCUIElement.perform(withKeyModifiers: .command) { beta.click() }
        let name = element("detail.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Alpha Bank")
    }

    func testShiftClickAndSelectAllUseNativeListSelection() {
        element("itemList.row.alpha").click()
        let gamma = element("itemList.row.gamma")
        XCUIElement.perform(withKeyModifiers: .shift) { gamma.click() }
        let summary = element("itemList.selectionSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "4 items selected")

        app.typeKey("a", modifierFlags: .command)
        XCTAssertEqual(summary.label, "5 items selected")
    }

    func testMultiSelectionDeleteConfirmationCanBeCancelled() {
        element("itemList.row.alpha").click()
        let beta = element("itemList.row.beta")
        XCUIElement.perform(withKeyModifiers: .command) { beta.click() }
        element("itemList.row.alpha").rightClick()
        let deleteAction = app.windows.firstMatch.menuItems["Delete"].firstMatch
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 3))
        deleteAction.click()

        let message = app.staticTexts["2 items will be moved to Trash."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertEqual(element("itemList.selectionSummary").label, "2 items selected")
        XCTAssertTrue(element("itemList.row.alpha").exists)
        XCTAssertTrue(element("itemList.row.beta").exists)

        element("itemList.row.alpha").rightClick()
        app.windows.firstMatch.menuItems["Archive"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["2 items will move to Archive and be hidden from your active vault and verification codes."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertEqual(element("itemList.selectionSummary").label, "2 items selected")
    }

    func testRightClickUnselectedRowTargetsOnlyThatItem() {
        element("itemList.row.alpha").click()
        let beta = element("itemList.row.beta")
        XCUIElement.perform(withKeyModifiers: .command) { beta.click() }
        element("itemList.row.gamma").rightClick()
        app.windows.firstMatch.menuItems["Delete"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["\"Gamma No Seed\" will be moved to Trash."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(element("itemList.row.gamma").exists)
    }

    func testSecureNoteEditorShowsAndEditsMultipleLines() {
        element("itemList.row.note").click()
        app.typeKey("e", modifierFlags: .command)
        let editor = app.textViews["edit.secureNote.body"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(editor.frame.height, 200)
        XCTAssertEqual(editor.value as? String, "First line\nSecond line\n\nFourth line")
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("Replacement\n\nLast line")
        XCTAssertEqual(editor.value as? String, "Replacement\n\nLast line")
        XCTAssertTrue(element("edit.button.save").isEnabled)

        element("edit.button.discard").click()
        let discardChanges = app.sheets.buttons["action-button-1"].firstMatch
        XCTAssertTrue(discardChanges.waitForExistence(timeout: 5))
        discardChanges.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "First line\nSecond line\n\nFourth line")
    }

    func testSavedColumnWidthsSurviveRelaunch() {
        app.terminate()
        app.launchArguments.append("--ui-test-layout")
        app.launch()
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 20))
        let dividers = columnDividers
        XCTAssertEqual(dividers.count, 2)
        let window = app.windows.firstMatch
        XCTAssertEqual(dividers[0].frame.minX - window.frame.minX, 260, accuracy: 3)
        XCTAssertEqual(dividers[1].frame.minX - dividers[0].frame.maxX, 340, accuracy: 3)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-test-layout" }
        app.launch()
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 20))
        let restored = columnDividers
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].frame.minX - window.frame.minX, 260, accuracy: 3)
        XCTAssertEqual(restored[1].frame.minX - restored[0].frame.maxX, 340, accuracy: 3)
    }
}
