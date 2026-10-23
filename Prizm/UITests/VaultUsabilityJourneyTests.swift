import XCTest

final class VaultUsabilityJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test-vault", "--ui-test-note", "-AppleLanguages", "(en)",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        print(app.debugDescription)
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private var columnDividers: [XCUIElement] {
        app.splitters.allElementsBoundByIndex
            .filter { $0.frame.height > 200 && $0.frame.width < 20 }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    func testArrowKeysNavigateImmediatelyAfterLaunch() {
        app.typeKey(.downArrow, modifierFlags: [])
        let name = element("detail.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Alpha Bank")

        app.typeKey(.downArrow, modifierFlags: [])
        let nextItem = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Beta Mail"), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [nextItem], timeout: 5), .completed)
        XCTAssertEqual(name.label, "Beta Mail")
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertEqual(name.label, "Alpha Bank")
    }

    func testSecureNoteEditorShowsAndEditsMultipleLines() {
        row("Omega Note").click()
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
        app.alerts.buttons["Discard Changes"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "First line\nSecond line\n\nFourth line")
    }

    func testWindowSizeAndColumnWidthsSurviveRelaunch() {
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -110, dy: -60)))
        XCTAssertLessThan(window.frame.height, originalFrame.height - 30)

        let splitters = columnDividers
        XCTAssertEqual(splitters.count, 2)
        let originalSidebarEdge = splitters[0].frame.minX
        for splitter in splitters {
            let start = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 45, dy: 0)))
        }
        XCTAssertGreaterThan(splitters[0].frame.minX, originalSidebarEdge + 20)
        let windowFrame = window.frame
        let sidebarWidth = splitters[0].frame.minX - windowFrame.minX
        let listWidth = splitters[1].frame.minX - splitters[0].frame.maxX

        app.terminate()
        app.launch()
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 20))
        XCTAssertEqual(window.frame.width, windowFrame.width, accuracy: 3)
        XCTAssertEqual(window.frame.height, windowFrame.height, accuracy: 3)
        let restoredDividers = columnDividers
        XCTAssertEqual(restoredDividers.count, 2)
        XCTAssertEqual(restoredDividers[0].frame.minX - window.frame.minX, sidebarWidth, accuracy: 3)
        XCTAssertEqual(restoredDividers[1].frame.minX - restoredDividers[0].frame.maxX, listWidth, accuracy: 3)
    }
}
