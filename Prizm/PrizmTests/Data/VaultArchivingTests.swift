import XCTest
@testable import Prizm

@MainActor
final class VaultArchivingTests: XCTestCase {
    private let timestamp = "2026-10-24T01:02:03.000Z"

    private func item(_ id: String, archived: Bool = false, deleted: Bool = false) -> VaultItem {
        VaultItem(id: id, name: id, isFavorite: true, isDeleted: deleted,
                  creationDate: .now, revisionDate: .now,
                  content: .login(LoginContent(username: nil, password: nil, uris: [],
                                               totp: "GEZDGNBVGY3TQOJQ", notes: nil, customFields: [])),
                  folderId: "folder", organizationId: "org", collectionIds: ["collection"],
                  archivedDate: archived ? timestamp : nil)
    }

    private func repository(_ items: [VaultItem], api: MockPrizmAPIClient = MockPrizmAPIClient()) async -> VaultRepositoryImpl {
        let sut = VaultRepositoryImpl(apiClient: api, crypto: MockPrizmCryptoService())
        await sut.populate(items: items, folders: [Folder(id: "folder", name: "Folder")],
                           organizations: [], collections: [OrgCollection(id: "collection", organizationId: "org", name: "Collection")],
                           syncedAt: .now)
        return sut
    }

    func testArchiveExcludedFromEveryActiveScopeAndSearch() async throws {
        let sut = await repository([item("active"), item("archived", archived: true), item("trashed", archived: true, deleted: true)])
        for scope: SidebarSelection in [.allItems, .favorites, .type(.login), .verificationCodes, .organization("org"), .collection("collection")] {
            let result = try await sut.items(for: scope)
            XCTAssertEqual(result.map(\.id), ["active"])
            let search = try await sut.searchItems(query: "archived", in: scope)
            XCTAssertTrue(search.isEmpty)
        }
        let archive = try await sut.items(for: .archive)
        XCTAssertEqual(archive.map(\.id), ["archived"])
        let search = try await sut.searchItems(query: "ARCH", in: .archive)
        XCTAssertEqual(search.map(\.id), ["archived"])
        let trash = try await sut.items(for: .trash)
        XCTAssertEqual(trash.map(\.id), ["trashed"])
        let counts = try await sut.itemCounts()
        XCTAssertEqual(counts[.archive], 1)
        XCTAssertEqual(counts[.allItems], 1)
        XCTAssertEqual(counts[.verificationCodes], 1)
    }

    func testArchivedDateSurvivesEncryptedEditRoundTrip() throws {
        let keys = CryptoKeys(encryptionKey: Data(repeating: 1, count: 32), macKey: Data(repeating: 2, count: 32))
        let mapper = CipherMapper()
        let original = item("archived", archived: true)
        let raw = try mapper.toRawCipher(DraftVaultItem(original), encryptedWith: keys)
        XCTAssertEqual(raw.archivedDate, timestamp)
        let (mapped, _) = try mapper.map(raw: raw, vaultKeys: keys, orgKeys: ["org": keys])
        XCTAssertTrue(mapped.isArchived)
        XCTAssertEqual(mapped.archivedDate, timestamp)
    }

    func testWireMetadataAbsentNullOrPresent() throws {
        for suffix in ["", ",\"archivedDate\":null", ",\"archivedDate\":\"\(timestamp)\""] {
            let json = "{\"id\":\"id\",\"type\":1,\"name\":\"encrypted\",\"favorite\":false\(suffix)}"
            let raw = try JSONDecoder().decode(RawCipher.self, from: Data(json.utf8))
            XCTAssertEqual(raw.archivedDate, suffix.contains(timestamp) ? timestamp : nil)
            let encoded = try JSONEncoder().encode(raw)
            let roundTrip = try JSONDecoder().decode(RawCipher.self, from: encoded)
            XCTAssertEqual(roundTrip.archivedDate, raw.archivedDate)
        }
    }

    func testCacheCopiesPreserveArchivedDate() async throws {
        let sut = await repository([item("archived", archived: true)])
        await sut.updateAttachments([], for: "archived")
        try await sut.moveItemToFolder(itemId: "archived", folderId: "other")
        try await sut.moveItemsToFolder(itemIds: ["archived"], folderId: "folder")
        try await sut.deleteFolder(id: "folder")
        try await sut.deleteItem(id: "archived")
        try await sut.restoreItem(id: "archived")
        let result = try await sut.itemDetail(id: "archived")
        XCTAssertEqual(result.archivedDate, timestamp)
        XCTAssertEqual(result.organizationId, "org")
        XCTAssertEqual(result.collectionIds, ["collection"])
        let active = try await sut.allItems()
        XCTAssertTrue(active.isEmpty)
    }
    func testArchiveAndUnarchiveUseServerStateAndRebuildIndexes() async throws {
        let api = MockPrizmAPIClient()
        let crypto = MockPrizmCryptoService()
        await crypto.unlockWith(keys: crypto.stubbedVaultKeys)
        let orgKeys = OrgKeyCache()
        await orgKeys.store(key: crypto.stubbedVaultKeys, for: "org")
        let sut = VaultRepositoryImpl(apiClient: api, crypto: crypto, orgKeyCache: orgKeys)
        let original = item("entry")
        await sut.populate(items: [original], folders: [], organizations: [], collections: [], syncedAt: .now)
        let useCase = ArchiveVaultItemUseCaseImpl(repository: sut)

        for archived in [true, false] {
            api.archiveResponse = try CipherMapper().toRawCipher(DraftVaultItem(item("entry", archived: archived)), encryptedWith: crypto.stubbedVaultKeys)
            try await useCase.execute(id: "entry", archived: archived)
            let detail = try await sut.itemDetail(id: "entry")
            XCTAssertEqual(detail.isArchived, archived)
            XCTAssertEqual(detail.archivedDate, archived ? timestamp : nil)
            XCTAssertEqual(detail.organizationId, original.organizationId)
            XCTAssertEqual(detail.collectionIds, original.collectionIds)
            let counts = try await sut.itemCounts()
            XCTAssertEqual(counts[.archive], archived ? 1 : 0)
            XCTAssertEqual(counts[.allItems], archived ? 0 : 1)
        }
        XCTAssertEqual(api.archiveCalls.map { $0.0 }, ["entry", "entry"])
        XCTAssertEqual(api.archiveCalls.map { $0.1 }, [true, false])
    }

    func testArchiveAndUnarchiveFailureLeaveCacheUnchanged() async throws {
        for archived in [false, true] {
            let api = MockPrizmAPIClient()
            let crypto = MockPrizmCryptoService()
            await crypto.unlockWith(keys: crypto.stubbedVaultKeys)
            let sut = VaultRepositoryImpl(apiClient: api, crypto: crypto)
            let original = item("entry", archived: archived)
            await sut.populate(items: [original], folders: [], organizations: [], collections: [], syncedAt: .now)
            api.archiveError = APIError.httpError(statusCode: 403, body: "unavailable")
            do {
                try await sut.setArchived(id: "entry", archived: !archived)
                XCTFail("Expected server error")
            } catch APIError.httpError(let status, _) {
                XCTAssertEqual(status, 403)
            }
            let detail = try await sut.itemDetail(id: "entry")
            XCTAssertEqual(detail, original)
        }
    }

    func testMissingTrashedAndLockedItemsDoNotCallArchiveAPI() async throws {
        let api = MockPrizmAPIClient()
        let sut = await repository([item("trashed", deleted: true), item("locked")], api: api)
        for id in ["missing", "trashed", "locked"] {
            do {
                try await sut.setArchived(id: id, archived: true)
                XCTFail("Expected validation failure for \(id)")
            } catch is VaultError { }
        }
        XCTAssertTrue(api.archiveCalls.isEmpty)
    }

    func testPersonalFolderScopesExcludeArchivedItems() async throws {
        let keys = CryptoKeys(encryptionKey: Data(repeating: 1, count: 32), macKey: Data(repeating: 2, count: 32))
        var personal: [VaultItem] = []
        for archived in [false, true] {
            var draft = DraftVaultItem(item(archived ? "archived" : "active", archived: archived))
            draft.organizationId = nil
            draft.collectionIds = []
            let raw = try CipherMapper().toRawCipher(draft, encryptedWith: keys)
            let (mapped, _) = try CipherMapper().map(raw: raw, keys: keys)
            personal.append(mapped)
        }
        let sut = await repository(personal)
        let folder = try await sut.items(for: .folder("folder"))
        XCTAssertEqual(folder.map(\.id), ["active"])
        let counts = try await sut.itemCounts()
        XCTAssertEqual(counts[.folder("folder")], 1)
    }

}
