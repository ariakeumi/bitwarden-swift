import XCTest
@testable import Prizm

@MainActor
final class PasswordGeneratorViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var provider: MockRandomnessProvider!
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "PasswordGeneratorViewModelTests")!
        defaults.removePersistentDomain(forName: "PasswordGeneratorViewModelTests")
        provider = MockRandomnessProvider()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.prizm.generator.tests.\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "PasswordGeneratorViewModelTests")
        pasteboard.releaseGlobally()
        try await super.tearDown()
    }

    func testInit_generatesValueImmediately() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        XCTAssertFalse(vm.generatedValue.isEmpty)
    }

    func testConfigChange_triggersRegeneration() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        let first = vm.generatedValue
        vm.length = 32
        // Value should change (different length = different output).
        XCTAssertNotEqual(vm.generatedValue.count, first.count)
    }

    func testModeSwitch_triggersRegeneration() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.mode = .passphrase
        XCTAssertTrue(vm.generatedValue.contains("-"))
    }

    func testCopyToClipboard_writesToPasteboard() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, pasteboard: pasteboard)
        vm.copyToClipboard()
        let pasted = pasteboard.string(forType: .string)
        XCTAssertEqual(pasted, vm.generatedValue)
        XCTAssertTrue(pasteboard.types?.contains(VaultBrowserViewModel.concealedType) == true)
        XCTAssertTrue(vm.hasCopied)
    }

    func testClearGeneratedValueReleasesPreviewAndRegenerateRestoresIt() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.clearGeneratedValue()
        XCTAssertTrue(vm.generatedValue.isEmpty)
        vm.generate()
        XCTAssertFalse(vm.generatedValue.isEmpty)
        XCTAssertFalse(vm.hasCopied)
    }

    func testPreviewExpires() async throws {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, sensitiveValueTimeout: .milliseconds(30))
        try await waitUntil { vm.generatedValue.isEmpty }
    }

    func testCopiedValueExpiresEvenAfterRegenerationAndModelRelease() async throws {
        var vm: PasswordGeneratorViewModel? = PasswordGeneratorViewModel(
            provider: provider, defaults: defaults, pasteboard: pasteboard, sensitiveValueTimeout: .milliseconds(60)
        )
        weak var releasedVM = vm
        vm?.copyToClipboard()
        vm?.length = 24
        vm?.clearGeneratedValue()
        vm = nil
        XCTAssertNil(releasedVM, "Clipboard cleanup must not retain the generated preview or its model")
        try await waitUntil { self.pasteboard.string(forType: .string) == nil }
    }

    func testClipboardExpirationPreservesNewerContents() async throws {
        let vm = PasswordGeneratorViewModel(
            provider: provider, defaults: defaults, pasteboard: pasteboard, sensitiveValueTimeout: .milliseconds(30)
        )
        vm.copyToClipboard()
        pasteboard.clearContents()
        pasteboard.setString("new clipboard contents", forType: .string)
        try await waitUntil { vm.generatedValue.isEmpty }
        XCTAssertEqual(pasteboard.string(forType: .string), "new clipboard contents")
    }

    func testEmptyPreviewCannotReplaceClipboardContents() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, pasteboard: pasteboard)
        vm.clearGeneratedValue()
        pasteboard.setString("existing clipboard contents", forType: .string)
        vm.copyToClipboard()
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard contents")
        XCTAssertFalse(vm.hasCopied)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    func testSettingsPersisted_toUserDefaults() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.length = 24
        vm.mode = .passphrase

        // Load a new VM from the same defaults — should restore.
        let provider2 = MockRandomnessProvider()
        let vm2 = PasswordGeneratorViewModel(provider: provider2, defaults: defaults)
        XCTAssertEqual(vm2.length, 24)
        XCTAssertEqual(vm2.mode, .passphrase)
    }

    func testDefaultsRestored_onFirstLaunch() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        XCTAssertEqual(vm.mode, .password)
        XCTAssertEqual(vm.length, 16)
        XCTAssertEqual(vm.wordCount, 6)
        XCTAssertTrue(vm.includeUppercase)
        XCTAssertTrue(vm.includeLowercase)
        XCTAssertTrue(vm.includeDigits)
        XCTAssertTrue(vm.includeSymbols)
        XCTAssertFalse(vm.avoidAmbiguous)
        XCTAssertEqual(vm.separator, "-")
        XCTAssertFalse(vm.capitalize)
        XCTAssertFalse(vm.includeNumber)
    }
}
