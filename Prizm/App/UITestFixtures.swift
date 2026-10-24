#if DEBUG
import Foundation

/// Seeds an in-memory vault for XCUITest, so UI journeys can run without a server or a login.
///
/// Enabled only by the `--ui-test-vault` launch argument and compiled out of Release builds
/// (`#if DEBUG`), so a shipping password manager contains no test-vault backdoor. The fixtures
/// use made-up names and RFC 6238 test secrets, never real credentials.
enum UITestFixtures {

    /// Isolates fixture sessions from the login keychain and its access prompts.
    final class InMemoryKeychain: KeychainService {
        private var values: [String: Data] = [:]

        func read(key: String) throws -> Data {
            guard let value = values[key] else { throw KeychainError.itemNotFound }
            return value
        }

        func write(data: Data, key: String) throws { values[key] = data }
        func delete(key: String) throws { values[key] = nil }
    }

    static let launchArgument = "--ui-test-vault"

    static var isEnabled: Bool { CommandLine.arguments.contains(launchArgument) }

    static func configureLayoutIfRequested() {
        guard isEnabled, CommandLine.arguments.contains("--ui-test-layout") else { return }
        UserDefaults.standard.set(260.0, forKey: "vault.layout.sidebarWidth")
        UserDefaults.standard.set(340.0, forKey: "vault.layout.itemListWidth")
    }

    /// With `--ui-test-open-codes`, start on the Codes list with its first item selected.
    static var opensOnCodes: Bool { CommandLine.arguments.contains("--ui-test-open-codes") }

    /// RFC 6238 Appendix B secret "12345678901234567890" in base32.
    static let rfcSeed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    /// With `--ui-test-no-codes`, every sample item has no TOTP seed (to see the empty state).
    static var withoutSeeds: Bool { CommandLine.arguments.contains("--ui-test-no-codes") }

    static var items: [VaultItem] {
        var all = seededItems
        if CommandLine.arguments.contains("--ui-test-note") {
            all.append(VaultItem(
                id: "note", name: "Omega Note", isFavorite: false, isDeleted: false,
                creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
                content: .secureNote(SecureNoteContent(
                    notes: "First line\nSecond line\n\nFourth line", customFields: []
                ))
            ))
        }
        guard withoutSeeds else { return all }
        return all.map { login(id: $0.id, name: $0.name, totp: nil, isDeleted: $0.isDeleted, archivedDate: $0.archivedDate) }
    }

    private static var seededItems: [VaultItem] {
        [
            login(id: "alpha", name: "Alpha Bank", totp: rfcSeed),
            login(id: "beta", name: "Beta Mail",
                  totp: "otpauth://totp/Beta:me?secret=\(rfcSeed)&digits=8&period=60&algorithm=SHA256"),
            login(id: "gamma", name: "Gamma No Seed", totp: nil),
            login(id: "delta", name: "Delta Bad Seed", totp: "not-a-seed!"),
            login(id: "archived", name: "Archived Account", totp: rfcSeed, archivedDate: "2026-10-24T01:02:03.000Z"),
            login(id: "zeta", name: "Zeta Trashed", totp: rfcSeed, isDeleted: true),
        ]
    }

    private static func login(id: String, name: String, totp: String?, isDeleted: Bool = false, archivedDate: String? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: isDeleted,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            content: .login(LoginContent(
                username: "user-\(id)", password: "pw-\(id)", uris: [], totp: totp, notes: nil, customFields: []
            )),
            archivedDate: archivedDate
        )
    }
}
#endif
