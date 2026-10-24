import AppKit
import XCTest

@MainActor
final class StandalonePasswordGeneratorJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test-vault", "-AppleLanguages", "(en)",
                               "-ApplePersistenceIgnoreState", "YES", "-pwgen.mode", "password",
                               "-vault.layout.columnVisibility", "all"]
        app.launch()
        if !element("create.button.newItem").waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(element("create.button.newItem").waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("itemList.row.alpha").waitForExistence(timeout: 20))
    }

    override func tearDown() async throws {
        app.terminate()
        app = nil
        try await super.tearDown()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private var generatorWindow: XCUIElement { app.windows["Password Generator"] }

    private var generatedValue: String {
        let preview = element("generator.preview")
        return preview.value as? String ?? preview.label
    }

    private func openGenerator() {
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(generatorWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(element("generator.preview").waitForExistence(timeout: 5))
    }

    func testShortcutOpensSingleWindowAndSupportsRegenerateAndCopy() {
        openGenerator()
        let initialValue = generatedValue
        XCTAssertFalse(initialValue.isEmpty)
        XCTAssertFalse(element("generator.button.use").exists)
        let screenshot = XCTAttachment(screenshot: generatorWindow.screenshot())
        screenshot.name = "Password Generator"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.typeKey("g", modifierFlags: .command)
        XCTAssertEqual(app.windows.matching(identifier: "Password Generator").count, 1)
        element("generator.button.refresh").click()
        let regenerated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialValue), object: element("generator.preview")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [regenerated], timeout: 3), .completed)

        let value = generatedValue
        element("generator.button.copy").click()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), value)
        XCTAssertTrue(NSPasteboard.general.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
    }

    func testCloseAndReopenGeneratesFreshValueAndKeepsOptions() {
        openGenerator()
        let previousValue = generatedValue
        let previousLength = previousValue.count
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(generatorWindow.waitForNonExistence(timeout: 5))

        openGenerator()
        XCTAssertNotEqual(generatedValue, previousValue)
        XCTAssertEqual(generatedValue.count, previousLength)
    }

    func testMenuOpensGeneratorAndPassphraseModeWorks() {
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menuItems["Password Generator"].click()
        XCTAssertTrue(generatorWindow.waitForExistence(timeout: 5))
        let modePicker = element("generator.modePicker")
        modePicker.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Passphrase")).firstMatch.click()
        XCTAssertTrue(element("generator.wordCount").waitForExistence(timeout: 3))
        XCTAssertTrue(generatedValue.contains("-"))
    }

    func testShortcutWorksWhileEditingAndInlineGeneratorStillApplies() {
        element("itemList.row.alpha").click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("edit.button.discard").waitForExistence(timeout: 5))

        openGenerator()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(generatorWindow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("edit.button.discard").exists)

        element("generator.button.trigger").click()
        XCTAssertTrue(element("generator.preview").waitForExistence(timeout: 5))
        element("generator.button.use").click()
        XCTAssertTrue(element("generator.preview").waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("edit.button.discard").exists)
    }
}
