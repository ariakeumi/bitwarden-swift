import AppKit
import XCTest
@testable import Prizm

@MainActor
final class WindowFramePersistenceTests: XCTestCase {
    func testWindowFrameIsAutosavedAndRestored() async throws {
        let name = "Bitvault.WindowFrameTest.\(UUID().uuidString)"
        defer { NSWindow.removeFrame(usingName: name) }
        let original = makeWindow()
        let bridge = MainWindowFramePersistence.FrameView()
        bridge.configure(original, autosaveName: name)
        XCTAssertEqual(original.frameAutosaveName, name)

        let expected = NSRect(x: 180, y: 160, width: 950, height: 650)
        original.setFrame(expected, display: false)
        original.close()
        original.setFrameAutosaveName("")
        try await Task.sleep(for: .milliseconds(100))

        let restored = makeWindow()
        defer { restored.close() }
        bridge.configure(restored, autosaveName: name)
        XCTAssertEqual(restored.frame.origin.x, expected.origin.x, accuracy: 1)
        XCTAssertEqual(restored.frame.origin.y, expected.origin.y, accuracy: 1)
        XCTAssertEqual(restored.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(restored.frame.height, expected.height, accuracy: 1)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
