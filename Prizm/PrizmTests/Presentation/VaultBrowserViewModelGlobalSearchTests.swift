import XCTest
@testable import Prizm

@MainActor
final class VaultBrowserViewModelGlobalSearchTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: VaultBrowserViewModel!

    private let sampleLogin = VaultItem(
        id: "1", name: "GitHub", isFavorite: false, isDeleted: false,
        creationDate: .now, revisionDate: .now,
        content: .login(LoginContent(username: "alice", password: nil, uris: [], totp: nil, notes: nil, customFields: []))
    )
    private let sampleCard = VaultItem(
        id: "2", name: "Visa", isFavorite: false, isDeleted: false,
        creationDate: .now, revisionDate: .now,
        content: .card(CardContent(cardholderName: "Alice", brand: nil, number: "4111111111111111", expMonth: nil, expYear: nil, code: nil, notes: nil, customFields: []))
    )

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        await vault.populate(items: [sampleLogin, sampleCard], folders: [], organizations: [], collections: [], syncedAt: .now)
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sut = VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            archive:         ArchiveVaultItemUseCaseImpl(repository: vault),
            delete:          DeleteVaultItemUseCaseImpl(repository: vault),
            permanentDelete: StubPermanentDeleteUseCase(),
            restore:         StubRestoreUseCase(),
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo)
        )
    }

    // MARK: - 1.1 activateGlobalSearch stores previous selection and sets flag

    func testActivateGlobalSearch_storesPreviousSelectionAndSetsFlag() {
        sut.sidebarSelection = .type(.login)
        sut.activateGlobalSearch()

        XCTAssertTrue(sut.isGlobalSearch)
        XCTAssertEqual(sut.previousSelection, .type(.login))
    }

    // MARK: - 1.2 deactivateGlobalSearch restores selection, clears query, resets flag

    func testDeactivateGlobalSearch_restoresSelectionAndClearsState() {
        sut.sidebarSelection = .favorites
        sut.activateGlobalSearch()
        sut.searchQuery = "test"

        sut.deactivateGlobalSearch()

        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.sidebarSelection, .favorites)
    }

    // MARK: - 1.3 search passes .allItems when isGlobalSearch is true

    func testGlobalSearch_searchesAllItems() async throws {
        sut.sidebarSelection = .type(.login)
        sut.activateGlobalSearch()
        sut.searchQuery = "Visa"

        // Yield twice: once for the outer Task spawned by searchQuery.didSet,
        // once for the inner Task spawned by refreshItems().
        await Task.yield()
        await Task.yield()

        // Visa is a Card, not a Login — should still appear in global search
        XCTAssertTrue(sut.displayedItems.contains(where: { $0.name == "Visa" }))
    }

    // MARK: - 1.4 sidebar selection change deactivates global search

    func testSidebarSelectionChange_deactivatesGlobalSearch() {
        sut.activateGlobalSearch()
        XCTAssertTrue(sut.isGlobalSearch)

        sut.sidebarSelection = .type(.card)

        XCTAssertFalse(sut.isGlobalSearch)
    }

    // MARK: - 1.5 escape/clear deactivates global search and restores selection

    func testDeactivateGlobalSearch_afterEscape_restoresSelection() {
        sut.sidebarSelection = .type(.identity)
        sut.activateGlobalSearch()
        sut.searchQuery = "something"

        // Simulate escape/clear
        sut.deactivateGlobalSearch()

        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertEqual(sut.sidebarSelection, .type(.identity))
        XCTAssertEqual(sut.searchQuery, "")
    }
    func testArchiveActionDelegatesAndClearsAffectedSelection() async {
        sut.itemSelection = sampleLogin
        await sut.performArchive(id: sampleLogin.id, archived: true)
        XCTAssertEqual(vault.archiveCalls.count, 1)
        XCTAssertEqual(vault.archiveCalls.first?.0, sampleLogin.id)
        XCTAssertEqual(vault.archiveCalls.first?.1, true)
        XCTAssertNil(sut.itemSelection)
        XCTAssertNil(sut.actionError)
    }

    func testUnarchiveFailureSurfacesErrorAndKeepsSelection() async {
        sut.itemSelection = sampleLogin
        vault.archiveError = VaultError.vaultLocked
        await sut.performArchive(id: sampleLogin.id, archived: false)
        XCTAssertEqual(sut.itemSelection, sampleLogin)
        XCTAssertEqual(sut.actionError, VaultError.vaultLocked.localizedDescription)
    }

    private func waitForItems(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while sut.displayedItems.count != count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(sut.displayedItems.count, count)
    }

    func testMultipleSelectionHidesSingleItemDetail() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id]
        XCTAssertEqual(sut.itemSelection, sampleLogin)

        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        XCTAssertEqual(sut.selectedItemIDs.count, 2)
        XCTAssertNil(sut.itemSelection)

        sut.selectedItemIDs.remove(sampleCard.id)
        XCTAssertEqual(sut.itemSelection, sampleLogin)
    }

    func testProgrammaticSingleSelectionUpdatesSelectedIDs() {
        sut.itemSelection = sampleCard
        XCTAssertEqual(sut.selectedItemIDs, [sampleCard.id])
        sut.itemSelection = nil
        XCTAssertTrue(sut.selectedItemIDs.isEmpty)
    }

    func testFilteringPrunesHiddenSelectionsAndRestoresSingleDetail() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        sut.searchQuery = "GitHub"
        try await waitForItems(1)

        XCTAssertEqual(sut.selectedItemIDs, [sampleLogin.id])
        XCTAssertEqual(sut.itemSelection, sampleLogin)
    }

    func testRefreshKeepsSelectionByIDWhenItemDataChanges() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id]
        let updated = VaultItem(
            id: sampleLogin.id, name: "Renamed login", isFavorite: true, isDeleted: false,
            creationDate: sampleLogin.creationDate, revisionDate: .now, content: sampleLogin.content
        )
        await vault.populate(items: [updated], folders: [], organizations: [], collections: [], syncedAt: .now)
        sut.refreshItems()
        try await waitForItems(1)

        XCTAssertEqual(sut.selectedItemIDs, [sampleLogin.id])
        XCTAssertEqual(sut.itemSelection, updated)
    }

    func testSidebarChangeAndLockClearMultipleSelection() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        sut.sidebarSelection = .favorites
        await Task.yield()
        XCTAssertTrue(sut.selectedItemIDs.isEmpty)

        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        sut.clearDecryptedState()
        XCTAssertTrue(sut.selectedItemIDs.isEmpty)
        XCTAssertNil(sut.itemSelection)
    }

    func testBatchDeleteRemovesOnlyRequestedItemsWithoutDuplicateWrites() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]

        await sut.performSoftDelete(ids: [sampleLogin.id, sampleLogin.id])
        try await waitForItems(1)

        XCTAssertEqual(vault.deleteCallCount, 1)
        XCTAssertEqual(vault.populatedItems.map(\.id), [sampleCard.id])
        XCTAssertEqual(sut.selectedItemIDs, [sampleCard.id])
        XCTAssertNil(sut.actionError)
    }

    func testBatchDeletePartialFailureKeepsFailedItemSelected() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        vault.stubbedDeleteErrorIDs = [sampleCard.id]

        await sut.performSoftDelete(ids: [sampleLogin.id, sampleCard.id])
        try await waitForItems(1)

        XCTAssertEqual(vault.deleteCallCount, 2)
        XCTAssertEqual(sut.selectedItemIDs, [sampleCard.id])
        XCTAssertEqual(sut.itemSelection, sampleCard)
        XCTAssertEqual(sut.actionError, VaultError.vaultLocked.localizedDescription)
    }

    func testBatchArchiveDelegatesForEverySelectedID() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]

        await sut.performArchive(ids: [sampleLogin.id, sampleCard.id], archived: true)

        XCTAssertEqual(Set(vault.archiveCalls.map { $0.0 }), [sampleLogin.id, sampleCard.id])
        XCTAssertTrue(vault.archiveCalls.allSatisfy { $0.1 })
        XCTAssertTrue(sut.selectedItemIDs.isEmpty)
        XCTAssertNil(sut.actionError)
    }

    func testBatchArchiveFailurePreservesSelection() async throws {
        try await waitForItems(2)
        sut.selectedItemIDs = [sampleLogin.id, sampleCard.id]
        vault.archiveError = VaultError.vaultLocked

        await sut.performArchive(ids: [sampleLogin.id, sampleCard.id], archived: false)

        XCTAssertEqual(sut.selectedItemIDs, [sampleLogin.id, sampleCard.id])
        XCTAssertEqual(sut.actionError, VaultError.vaultLocked.localizedDescription)
    }

}

// MARK: - Stub use cases (minimal, no-op)

private final class StubPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}

private final class StubRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}

private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
