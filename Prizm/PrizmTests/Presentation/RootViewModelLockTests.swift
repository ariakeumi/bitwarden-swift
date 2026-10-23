import XCTest
@testable import Prizm

/// Unit tests for `RootViewModel.lockVault()`.
@MainActor
final class RootViewModelLockTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
    private var sut: RootViewModel!

    private let stubAccount = Account(
        userId: "user-001",
        email: "alice@example.com",
        name: nil,
        serverEnvironment: ServerEnvironment(
            base: URL(string: "https://vault.example.com")!,
            overrides: nil
        )
    )

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockAuthRepository()
        mockVault = MockVaultRepository()
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut = RootViewModel(container: deps)
    }

    /// Yields to the main actor run loop until `condition` returns true or timeout.
    /// Replaces fixed `Task.sleep` which is flaky under parallel test execution
    /// when multiple actor hops are involved (e.g. lockVault → authRepo → vaultKeyCache → orgKeyCache).
    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testLaunchRestoresNeverSessionAndManualLockDoesNotRestoreAgain() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        mockAuth.vaultLockPolicy = .never
        mockAuth.stubbedRestoredAccount = stubAccount
        sut = RootViewModel(container: MockRootDependencies(auth: mockAuth, vault: mockVault))
        try await waitUntil { if case .vault = self.sut.screen { return true }; return false }
        guard case .vault = sut.screen else { return XCTFail("Session should restore into the vault") }
        XCTAssertEqual(mockAuth.restoreSessionCallCount, 1)

        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }
        guard case .unlock = sut.screen else { return XCTFail("Manual lock must stay locked") }
        XCTAssertEqual(mockAuth.restoreSessionCallCount, 1)
    }

    func testLaunchWithMissingOrFailedRetainedSessionRequiresUnlock() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        mockAuth.vaultLockPolicy = .onRestart
        mockAuth.restoreSessionError = AuthError.sessionRetentionFailed
        sut = RootViewModel(container: MockRootDependencies(auth: mockAuth, vault: mockVault))
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }
        guard case .unlock = sut.screen else { return XCTFail("Failed restoration must require unlock") }
        XCTAssertTrue(mockAuth.restoreSessionCalled)
    }

    func testSidebarNavigationExitsGlobalSearchEvenForSameCategory() {
        sut.screen = .vault
        sut.vaultBrowserVM.sidebarSelection = .allItems
        sut.vaultBrowserVM.activateGlobalSearch()
        sut.vaultBrowserVM.searchQuery = "query"

        sut.navigateToSidebar(.allItems)

        XCTAssertEqual(sut.vaultBrowserVM.sidebarSelection, .allItems)
        XCTAssertFalse(sut.vaultBrowserVM.isGlobalSearch)
        XCTAssertTrue(sut.vaultBrowserVM.searchQuery.isEmpty)
    }

    func testSidebarNavigationDoesNotChangeSelectionWhileLocked() {
        sut.screen = .unlock
        sut.vaultBrowserVM.sidebarSelection = .allItems

        sut.navigateToSidebar(.trash)

        XCTAssertEqual(sut.vaultBrowserVM.sidebarSelection, .allItems)
        XCTAssertFalse(sut.canNavigateSidebar)
    }

    func testSidebarNavigationDoesNotSwitchAwayFromAnOpenEditor() {
        sut.screen = .vault
        sut.vaultBrowserVM.sidebarSelection = .allItems
        sut.vaultBrowserVM.handleEditSheetState(true)

        sut.navigateToSidebar(.favorites)

        XCTAssertEqual(sut.vaultBrowserVM.sidebarSelection, .allItems)
        XCTAssertFalse(sut.canNavigateSidebar)
    }

    func testSidebarNavigationSelectsRequestedCategory() {
        sut.screen = .vault
        sut.navigateToSidebar(.verificationCodes)
        XCTAssertEqual(sut.vaultBrowserVM.sidebarSelection, .verificationCodes)
    }

    func testManualSyncUpdatesTimestampOnSuccess() async throws {
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        deps.mockSyncUseCase.stubbedResult = SyncResult(syncedAt: date, totalCiphers: 1, failedDecryptionCount: 0)
        sut = RootViewModel(container: deps)
        await Task.yield()
        sut.screen = .vault

        sut.syncVault()
        try await waitUntil { !self.sut.isManualSyncInProgress }

        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 1)
        XCTAssertEqual(sut.vaultBrowserVM.lastSyncedAt, date)
        XCTAssertNil(sut.vaultBrowserVM.syncErrorMessage)
    }

    func testManualSyncFailurePreservesLastSuccessfulTimestamp() async throws {
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        deps.mockSyncUseCase.executeError = SyncError.networkUnavailable
        sut = RootViewModel(container: deps)
        await Task.yield()
        sut.screen = .vault
        let previous = Date(timeIntervalSince1970: 1_000)
        sut.vaultBrowserVM.handleSyncCompleted(syncedAt: previous)

        sut.syncVault()
        try await waitUntil { !self.sut.isManualSyncInProgress }

        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 1)
        XCTAssertEqual(sut.vaultBrowserVM.lastSyncedAt, previous)
        XCTAssertEqual(sut.vaultBrowserVM.syncErrorMessage, SyncError.networkUnavailable.localizedDescription)
    }

    func testManualSyncDoesNotRunWhenLockedOrEditing() {
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut = RootViewModel(container: deps)
        sut.screen = .unlock
        sut.syncVault()
        XCTAssertFalse(sut.isManualSyncInProgress)
        XCTAssertFalse(sut.canSyncVault)

        sut.screen = .vault
        sut.vaultBrowserVM.handleEditSheetState(true)
        sut.syncVault()
        XCTAssertFalse(sut.isManualSyncInProgress)
        XCTAssertFalse(sut.canSyncVault)
        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 0)
    }

    func testRepeatedManualSyncIsIgnoredAndLockCancelsPendingSync() async throws {
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        deps.mockSyncUseCase.executeDelay = .seconds(10)
        sut = RootViewModel(container: deps)
        await Task.yield()
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault

        sut.syncVault()
        sut.syncVault()
        XCTAssertFalse(sut.canSyncVault)
        try await waitUntil { deps.mockSyncUseCase.executeCallCount == 1 }
        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }

        guard case .unlock = sut.screen else { return XCTFail("Lock must finish after cancelling manual sync") }
        XCTAssertFalse(sut.isManualSyncInProgress)
        XCTAssertNil(sut.vaultBrowserVM.syncErrorMessage)
        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 1)
    }

    // MARK: - 1.1 lockVault() transitions screen to .unlock

    func testLockVault_transitionsToUnlock() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }

    // MARK: - 1.2 lockVault() is a no-op when screen != .vault

    func testLockVault_noOpWhenLogin() async throws {
        sut.screen = .login
        sut.lockVault()
        // Fixed sleep (not polling) because this is a no-op test — there is no positive
        // state change to poll for. 50ms is enough for the guard-return fast path.
        try await Task.sleep(for: .milliseconds(50))

        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
    }

    func testLockVault_noOpWhenUnlock() async throws {
        sut.screen = .unlock
        sut.lockVault()
        // Fixed sleep (not polling) because this is a no-op test — there is no positive
        // state change to poll for. 50ms is enough for the guard-return fast path.
        try await Task.sleep(for: .milliseconds(50))

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }

    // MARK: - 1.3 lockVault() calls authRepository.lockVault() and vaultStore.clearVault()

    func testLockVault_callsLockAndClear() async throws {
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { self.mockAuth.lockVaultCalledCount >= 1 }

        XCTAssertEqual(mockAuth.lockVaultCalledCount, 1)
        XCTAssertTrue(mockVault.clearVaultCalled)
    }

    // MARK: - 1.4 lockVault() creates a new unlockVM from the stored account

    func testLockVault_createsUnlockVM() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault
        sut.unlockVM = nil

        sut.lockVault()
        try await waitUntil { self.sut.unlockVM != nil }

        XCTAssertNotNil(sut.unlockVM)
    }

    // MARK: - 1.5 lockVault() falls back to .login when storedAccount() returns nil

    func testLockVault_fallsBackToLogin_whenNoStoredAccount() async throws {
        mockAuth.stubbedStoredAccount = nil
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { if case .login = self.sut.screen { return true }; return false }

        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
    }

    // MARK: - lockVault() works from .syncing state

    func testLockVault_worksFromSyncing() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .syncing(message: "Syncing…")

        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }
}

// MARK: - Mock Dependencies

@MainActor
final class MockRootDependencies: RootViewModelDependencies {
    /// Replaceable so copy-code tests can inject a deterministic generator.
    var generateTOTPCode: any GenerateTOTPCodeUseCase = UnusedGenerateTOTPCode()
    let authRepo: any AuthRepository
    let vaultRepo: any VaultRepository
    let vaultKeyCache = VaultKeyCache()
    let orgKeyCache   = OrgKeyCache()

    private let mockLoginUseCase = MockLoginUseCase()
    let mockSyncUseCase = MockSyncUseCase()
    var syncVaultUseCase: any SyncUseCase { mockSyncUseCase }
    private let mockVault: MockVaultRepository

    init(auth: MockAuthRepository, vault: MockVaultRepository) {
        self.authRepo = auth
        self.vaultRepo = vault
        self.mockVault = vault
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(loginUseCase: mockLoginUseCase)
    }

    func makeUnlockViewModel(account: Account) -> UnlockViewModel {
        UnlockViewModel(auth: authRepo as! MockAuthRepository, sync: mockSyncUseCase, account: account)
    }

    func makeVaultBrowserViewModel() -> VaultBrowserViewModel {
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        return VaultBrowserViewModel(
            vault:           mockVault,
            search:          StubSearchUseCase(),
            archive:         ArchiveVaultItemUseCaseImpl(repository: mockVault),
            delete:          StubDeleteUseCase(),
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

    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase) {
        let repo = MockSyncTimestampRepository(storedDate: nil)
        return (repo, GetLastSyncDateUseCaseImpl(repository: repo))
    }
}

// Minimal stubs for VaultBrowserViewModel dependencies.
@MainActor private final class StubSearchUseCase: SearchVaultUseCase {
    func execute(query: String, in selection: SidebarSelection) throws -> [VaultItem] { [] }
}
@MainActor private final class StubDeleteUseCase: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class StubPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class StubRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
@MainActor private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
@MainActor private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
@MainActor private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}

/// Default generator for tests that never generate a code.
private struct UnusedGenerateTOTPCode: GenerateTOTPCodeUseCase {
    func execute(seed: String, at date: Date) async throws -> TOTPCode {
        throw TOTPError.invalidSecret
    }
}
