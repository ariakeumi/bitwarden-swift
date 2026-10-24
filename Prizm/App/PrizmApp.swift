//
//  PrizmApp.swift
//  Prizm
//
//  Created by Benjamin on 15.03.26.
//

import AppKit
import Combine
import SwiftUI
import os.log

@main
struct PrizmApp: App {

    @StateObject private var container: AppContainer
    @StateObject private var rootVM:    RootViewModel
    @State       private var optionKeyMonitor = OptionKeyMonitor()

    // Opens auxiliary windows from their menu commands.
    @Environment(\.openWindow) private var openWindow

    init() {
        #if DEBUG
        UITestFixtures.configureLayoutIfRequested()
        #endif
        let c = AppContainer()
        _container = StateObject(wrappedValue: c)
        _rootVM    = StateObject(wrappedValue: RootViewModel(container: c))
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Bitvault", id: "vault") {
            rootView
                .frame(minWidth: 480, minHeight: 360)
                .background(MainWindowFramePersistence())
                .environment(optionKeyMonitor)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Replace the default "About Bitvault" panel with our custom SwiftUI window.
            CommandGroup(replacing: .appInfo) {
                Button("About Bitvault") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "vault")
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .newItem) {
                Button("Password Generator") {
                    openWindow(id: "password-generator")
                }
                .keyboardShortcut("g", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Sign Out…") {
                    rootVM.confirmSignOut()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(!rootVM.isSignedIn)

                Button("Lock Vault") {
                    rootVM.lockVault()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!rootVM.isVaultUnlocked)

                Button("Sync Vault") {
                    rootVM.syncVault()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!rootVM.canSyncVault)
            }

            CommandMenu("Navigate") {
                ForEach(Array(SidebarSelection.shortcutDestinations.enumerated()), id: \.element) { entry in
                    Button(entry.element.displayName) {
                        rootVM.navigateToSidebar(entry.element)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(entry.offset + 1))), modifiers: .command)
                }
                .disabled(!rootVM.canNavigateSidebar)
            }

            // "Item" menu — sits in the standard macOS menu bar next to Edit/View/Window.
            // Edit opens the edit sheet for the selected vault item (⌘E).
            // Save persists in-flight edits (⌘S).
            // Buttons are disabled by `rootVM` Combine subscriptions that track
            // item selection and edit-sheet state.
            CommandMenu("Item") {
                Button("Edit") {
                    rootVM.vaultBrowserVM.triggerEdit()
                }
                .disabled(!rootVM.menuBarCanEdit)
                .keyboardShortcut("e", modifiers: .command)

                Button("Save") {
                    rootVM.vaultBrowserVM.triggerSave()
                }
                .disabled(!rootVM.menuBarCanSave)
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Copy Username") {
                    rootVM.copySelectedField(.username)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.username))

                Button("Copy Password") {
                    rootVM.copySelectedField(.password)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!rootVM.selectedFieldAvailable(.password))

                Button("Copy Code") {
                    rootVM.copySelectedField(.totp)
                }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(!rootVM.selectedFieldAvailable(.totp))

                Button("Copy Website") {
                    rootVM.copySelectedField(.website)
                }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.website))
            }
        }

        Window("Password Generator", id: "password-generator") {
            PasswordGeneratorWindow(provider: CryptographicRandomnessProvider())
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // Custom About window — opened via Prizm → About Bitvault.
        // hiddenTitleBar: AboutView provides its own header with the app icon and name,
        // so the system title bar would be redundant.
        // contentSize resizability: window sizes to AboutView's fixed 380pt width; no
        // free resize since the content is a fixed-layout info panel.
        Window("About Bitvault", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings window — opened via ⌘, (macOS convention) or the gear toolbar button.
        // The Settings scene does not inherit the WindowGroup environment, so we pass
        // the container explicitly via .environmentObject().
        Settings {
            SettingsView(authRepository: container.authRepository)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch rootVM.screen {
        case .login:
            LoginView(viewModel: rootVM.loginVM)

        case .loading:
            ProgressView("Signing in…")
                .frame(minWidth: 480, minHeight: 360)

        case .totpPrompt:
            TOTPPromptView(viewModel: rootVM.loginVM)

        case .unlock:
            if let unlockVM = rootVM.unlockVM {
                UnlockView(viewModel: unlockVM)
            }

        case .syncing(let message):
            SyncProgressView(message: message)

        case .vault:
            VaultBrowserView(
                viewModel:         rootVM.vaultBrowserVM,
                faviconLoader:     container.faviconLoader,
                makeEditViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] item in
                    let vm = container.makeItemEditViewModel(
                        for: item,
                        folders: vaultBrowserVM.folders,
                        organizations: vaultBrowserVM.organizations,
                        collections: vaultBrowserVM.collections
                    )
                    // Wire the list-pane refresh callback to the shared VaultBrowserViewModel.
                    vm.onSaveSuccess = { [weak vaultBrowserVM] updatedItem in
                        vaultBrowserVM?.handleItemSaved(updatedItem)
                    }
                    return vm
                },
                makeCreateViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] type, contextId in
                    // contextId is either a folderId (personal item) or collectionId (org item),
                    // determined by whether the current sidebar selection is a collection.
                    let cols = vaultBrowserVM.collections
                    let isCollection = contextId != nil && cols.contains(where: { $0.id == contextId })
                    let vm: ItemEditViewModel
                    if isCollection {
                        vm = container.makeItemCreateViewModel(
                            for: type, collectionId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    } else {
                        vm = container.makeItemCreateViewModel(
                            for: type, folderId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    }
                    vm.onSaveSuccess = { [weak vaultBrowserVM] item in
                        vaultBrowserVM?.handleItemSaved(item)
                    }
                    return vm
                },
                makeAddAttachmentViewModel: { cipherId in
                    container.makeAddAttachmentViewModel(for: cipherId)
                },
                makeBatchAttachmentViewModel: { cipherId in
                    container.makeBatchAttachmentViewModel(for: cipherId)
                },
                makeAttachmentRowViewModel: { cipherId, attachment in
                    container.makeAttachmentRowViewModel(cipherId: cipherId, attachment: attachment)
                },
                makeCodesViewModel: { container.makeTOTPCodesViewModel() },
                isSyncing: rootVM.isSyncInProgress
            )
            .background(VaultColumnLayoutRestorer(viewModel: rootVM.vaultBrowserVM))
        }
    }
}

/// NavigationSplitView treats ideal widths as suggestions. Restore actual divider
/// positions after its initial layout, then leave native divider dragging in control.
private struct VaultColumnLayoutRestorer: NSViewRepresentable {
    @ObservedObject var viewModel: VaultBrowserViewModel
    @AppStorage("vault.layout.columnVisibility") private var visibility = "all"

    func makeNSView(context: Context) -> SplitViewReader { SplitViewReader() }
    func updateNSView(_ view: SplitViewReader, context: Context) {
        view.restore(showsCodes: viewModel.sidebarSelection == .verificationCodes, visibility: visibility)
    }

    final class SplitViewReader: NSView {
        private var requestedMode = false
        private var requestedVisibility = "all"
        private var restoredMode: Bool?
        private var restoredVisibility: String?
        private var restoreTask: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { restore(showsCodes: requestedMode, visibility: requestedVisibility) }
        }

        func restore(showsCodes: Bool, visibility: String) {
            requestedMode = showsCodes
            requestedVisibility = visibility
            guard window != nil, restoredMode != showsCodes || restoredVisibility != visibility else { return }
            restoredMode = showsCodes
            restoredVisibility = visibility
            restoreTask?.cancel()
            guard visibility != "detailOnly" else { return }
            let defaults = UserDefaults.standard
            let sidebar = min(420, max(180, defaults.object(forKey: "vault.layout.sidebarWidth") as? Double ?? 210))
            let key = showsCodes ? "vault.layout.codesListWidth" : "vault.layout.itemListWidth"
            let content = min(720, max(showsCodes ? 360 : 220, defaults.object(forKey: key) as? Double ?? (showsCodes ? 420 : 280)))
            restoreTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let root = self.window?.contentView else { return }
                let splits = self.verticalSplits(in: root)
                guard let outer = splits.first else { return }
                if visibility != "doubleColumn" {
                    outer.setPosition(sidebar, ofDividerAt: 0)
                }
                if outer.subviews.count >= 3 {
                    let offset = visibility == "doubleColumn" ? 0 : sidebar + outer.dividerThickness
                    outer.setPosition(offset + content, ofDividerAt: 1)
                } else if splits.count > 1 {
                    splits[1].setPosition(content, ofDividerAt: 0)
                }
            }
        }

        private func verticalSplits(in view: NSView) -> [NSSplitView] {
            var result: [NSSplitView] = []
            if let split = view as? NSSplitView, split.isVertical, split.subviews.count >= 2 {
                result.append(split)
            }
            return result + view.subviews.flatMap { verticalSplits(in: $0) }
        }
    }
}

/// SwiftUI's defaultSize only supplies the initial size; AppKit autosave also
/// restores the user's last position and size across the root screen changes.
struct MainWindowFramePersistence: NSViewRepresentable {
    func makeNSView(context: Context) -> FrameView { FrameView() }
    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // SwiftUI finishes configuring its window after attaching the content.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.configure(window)
            }
        }

        func configure(_ window: NSWindow, autosaveName baseName: String = "Bitvault.MainWindow") {
            guard !window.frameAutosaveName.hasPrefix(baseName) else { return }
            // Each open window needs its own autosave name.
            let usedNames = Set(NSApp.windows.filter { $0 !== window }.map(\.frameAutosaveName))
            var name = baseName
            var index = 2
            while usedNames.contains(name) {
                name = "\(baseName).\(index)"
                index += 1
            }
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
    }
}

// MARK: - RootViewModel

/// Dependencies required by `RootViewModel` — extracted for testability.
@MainActor
protocol RootViewModelDependencies: AnyObject {
    var authRepo: any AuthRepository { get }
    var vaultRepo: any VaultRepository { get }
    var syncVaultUseCase: any SyncUseCase { get }
    /// Generates the current TOTP code for the "Copy Code" command.
    var generateTOTPCode: any GenerateTOTPCodeUseCase { get }
    /// The per-cipher attachment key cache. Cleared on vault lock alongside the vault store.
    var vaultKeyCache: VaultKeyCache { get }
    /// The per-organisation symmetric key cache. Cleared on vault lock alongside the vault store.
    var orgKeyCache: OrgKeyCache { get }
    func makeLoginViewModel() -> LoginViewModel
    func makeUnlockViewModel(account: Account) -> UnlockViewModel
    func makeVaultBrowserViewModel() -> VaultBrowserViewModel
    /// Returns a fresh sync timestamp repository and use case scoped to the given email.
    /// Called after login/unlock to re-scope to the correct account before the first sync.
    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase)
}

extension AppContainer: RootViewModelDependencies {
    var authRepo: any AuthRepository { authRepository }
    var vaultRepo: any VaultRepository { vaultStore }
    var syncVaultUseCase: any SyncUseCase { syncUseCase }
    var generateTOTPCode: any GenerateTOTPCodeUseCase { generateTOTPCodeUseCase }
}

/// Top-level state machine that decides which screen to show.
///
/// On launch: checks for a stored session via `AuthRepository.storedAccount()`.
/// - Session found → restore if the lock policy permits, otherwise `UnlockView`
/// - No session    → `LoginView`  (User Story 1)
@MainActor
final class RootViewModel: ObservableObject {

    enum Screen {
        case login
        case loading
        case totpPrompt
        case unlock
        case syncing(message: String)
        case vault
    }

    @Published var screen: Screen
    @Published private(set) var isSyncInProgress = false
    private var syncTask: Task<Void, Never>?
    private var isEndingSession = false

    // MARK: - "Item" menu state

    /// Whether the Edit command should be enabled: an item is selected and the edit sheet is closed.
    @Published private(set) var menuBarCanEdit: Bool = false

    /// Whether the Save command should be enabled: the edit sheet is currently open.
    @Published private(set) var menuBarCanSave: Bool = false

    /// The login content of the currently selected item, or nil. Drives copy command disabled state.
    @Published private(set) var selectedLogin: LoginContent?

    private let logger = Logger(subsystem: "com.prizm", category: "RootViewModel")

    let loginVM:          LoginViewModel
    @Published var unlockVM: UnlockViewModel?
    let vaultBrowserVM:   VaultBrowserViewModel

    private let container: any RootViewModelDependencies
    /// Combine subscriptions — held for the lifetime of this object.
    /// Using Combine (not SwiftUI .onChange) so transitions fire regardless
    /// of whether the source view is currently in the view hierarchy.
    private var cancellables = Set<AnyCancellable>()
    init(container: any RootViewModelDependencies) {
        self.container      = container
        self.loginVM        = container.makeLoginViewModel()
        self.vaultBrowserVM = container.makeVaultBrowserViewModel()

        // Check for stored session at launch.
        if let account = container.authRepo.storedAccount() {
            self.screen   = .unlock
            self.unlockVM = container.makeUnlockViewModel(account: account)
            self.unlockVM?.restoreSessionIfAllowed()
            if container.authRepo.vaultLockPolicy != .onReopen {
                self.screen = .loading
            }
        } else {
            self.screen   = .login
            self.unlockVM = nil
        }

        subscribeToFlowStates()

        #if DEBUG
        // XCUITest seam: skip login and show a seeded in-memory vault (see UITestFixtures).
        if UITestFixtures.isEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await container.vaultRepo.populate(
                    items: UITestFixtures.items, folders: [], organizations: [],
                    collections: [], syncedAt: Date()
                )
                self.transitionToVault(caller: "UITestFixtures")

                // Optional: open straight on the Codes list with an item selected (screenshots).
                if UITestFixtures.opensOnCodes {
                    try? await Task.sleep(for: .milliseconds(600))
                    self.vaultBrowserVM.sidebarSelection = .verificationCodes
                    try? await Task.sleep(for: .milliseconds(600))
                    self.vaultBrowserVM.itemSelection = self.vaultBrowserVM.displayedItems.first
                }
            }
        }
        #endif
    }

    // MARK: - Combine subscriptions

    private func subscribeToFlowStates() {
        // Login flow — observe for the lifetime of the app (loginVM is never replaced).
        loginVM.$flowState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleLoginFlow(state) }
            .store(in: &cancellables)

        // Unlock flow — re-subscribe whenever unlockVM is assigned.
        $unlockVM
            .compactMap { $0 }
            .flatMap { $0.$flowState }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleUnlockFlow(state) }
            .store(in: &cancellables)

        // canEdit: item selected AND edit sheet not yet open.
        // canSave: edit sheet is open.
        // Both are derived by watching editSheetOpen and itemSelection independently.
        // `for await` on @Published.values avoids Combine callbacks (CLAUDE.md async/await rule).
        Task { [weak self, vaultBrowserVM] in
            for await open in vaultBrowserVM.$editSheetOpen.values {
                guard let self else { break }
                self.menuBarCanSave = open
                self.menuBarCanEdit = vaultBrowserVM.itemSelection != nil && !open
            }
        }
        Task { [weak self, vaultBrowserVM] in
            for await selection in vaultBrowserVM.$itemSelection.values {
                guard let self else { break }
                self.menuBarCanEdit = selection != nil && !vaultBrowserVM.editSheetOpen
                if case .login(let login) = selection?.content {
                    self.selectedLogin = login
                } else {
                    self.selectedLogin = nil
                }
            }
        }

        // Automatic locking is defined by the persisted restart/reopen policy.
        // Sleep, screensaver and screen lock do not cross either boundary.
    }

    /// Re-scopes the timestamp and opens the vault. Returning sessions sync in the
    /// background; initial login has already synchronized through LoginUseCase.
    ///
    /// `caller` identifies the originating flow if the stored account is missing.
    private func transitionToVault(caller: String, syncOnEntry: Bool = false) {
        // Re-scope before recording: on first login the AppContainer was initialised without
        // a known email; this corrects the UserDefaults key before handleSyncCompleted writes to it.
        if let email = container.authRepo.storedAccount()?.email {
            let deps = container.makeSyncTimestampDependencies(for: email)
            vaultBrowserVM.updateSyncTimestamp(repository: deps.repository, useCase: deps.useCase)
        } else {
            // Unexpected: vault transition reached with no stored account — timestamp will
            // be written under the fallback empty-email key. Should not occur in normal flow.
            logger.error("\(caller, privacy: .public)(.vault): no stored account; sync timestamp not re-scoped")
        }
        screen = .vault
        // Defer sync work to the next run-loop cycle so that the initial
        // VaultBrowserView layout pass (triggered by `screen = .vault` above) commits
        // before any @Published mutations from async vault reads arrive.
        //
        // Root cause: VaultRepositoryImpl is an `actor`, so every refresh Task suspends
        // at a cross-actor hop; the continuations resume on @MainActor asynchronously.
        // If they land while SwiftUI is computing its first layout pass for VaultBrowserView,
        // SwiftUI emits "Publishing changes from within view updates is not allowed" →
        // undefined behaviour → heap corruption → z_ccm_xcma_malloc_freelist EXC_BREAKPOINT.
        //
        // DispatchQueue.main.async (not a Swift Task) is intentional: it guarantees
        // the block runs between run-loop iterations, after the current CATransaction
        // (which drives the SwiftUI layout commit) has flushed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard case .vault = self.screen, !self.isEndingSession else { return }
                if syncOnEntry {
                    self.startVaultSync()
                } else {
                    self.vaultBrowserVM.handleSyncCompleted(syncedAt: Date())
                }
            }
        }
    }

    func handleLoginFlow(_ state: LoginFlowState) {
        switch state {
        case .login:       screen = .login
        case .loading:     screen = .loading
        case .totpPrompt:  screen = .totpPrompt
        case .syncing(let msg): screen = .syncing(message: msg)
        case .vault:       transitionToVault(caller: "handleLoginFlow")
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    /// Whether the user has an active session (vault or unlock screen).
    var isSignedIn: Bool {
        switch screen {
        case .vault, .unlock, .syncing: return true
        default: return false
        }
    }

    /// Shows a confirmation alert before signing out (FR-014).
    func confirmSignOut() {
        let alert = NSAlert()
        alert.messageText = "Sign Out"
        alert.informativeText = "All local data will be cleared."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        signOut()
    }

    /// Clears all session data and returns to the login screen.
    func signOut() {
        guard !isEndingSession else { return }
        isEndingSession = true
        let pendingSync = syncTask
        pendingSync?.cancel()
        Task {
            defer { isEndingSession = false }
            await pendingSync?.value
            do {
                try await container.authRepo.signOut()
            } catch {
                logger.error("Sign-out error: \(error.localizedDescription, privacy: .public)")
            }
            await container.vaultRepo.clearVault()
            await container.vaultKeyCache.clear()
            await container.orgKeyCache.clear()
            vaultBrowserVM.clearDecryptedState()
            unlockVM = nil
            screen   = .login
            logger.info("Sign out completed")
        }
    }

    // MARK: - Sidebar navigation

    var canNavigateSidebar: Bool {
        guard case .vault = screen, !isEndingSession else { return false }
        return !vaultBrowserVM.editSheetOpen
    }

    func navigateToSidebar(_ selection: SidebarSelection) {
        guard canNavigateSidebar else { return }
        // Global search deselects the sidebar, even when its saved destination matches.
        vaultBrowserVM.deactivateGlobalSearch(restoreSelection: false)
        vaultBrowserVM.sidebarSelection = selection
    }

    // MARK: - Vault sync

    var canSyncVault: Bool {
        canNavigateSidebar && !isSyncInProgress
    }

    func syncVault() {
        guard canSyncVault else { return }
        startVaultSync()
    }

    /// Startup and manual sync share one task so lock/sign-out can cancel and drain
    /// every vault write before releasing the session's keys.
    private func startVaultSync() {
        guard case .vault = screen, !isSyncInProgress, !isEndingSession else { return }
        isSyncInProgress = true
        syncTask = Task {
            defer {
                isSyncInProgress = false
                syncTask = nil
            }
            do {
                let result = try await container.syncVaultUseCase.execute(progress: { _ in })
                guard !Task.isCancelled, !isEndingSession else { return }
                vaultBrowserVM.handleSyncCompleted(syncedAt: result.syncedAt)
            } catch {
                guard !Task.isCancelled, !isEndingSession else { return }
                vaultBrowserVM.handleSyncError(error.localizedDescription)
                logger.error("Vault sync failed")
            }
        }
    }

    // MARK: - Lock

    /// Zeros in-memory key material, clears the vault cache, and transitions to the unlock screen.
    /// No-op if the vault is not currently unlocked.
    func lockVault() {
        guard isVaultUnlocked, !isEndingSession else { return }
        isEndingSession = true
        let pendingSync = syncTask
        pendingSync?.cancel()
        Task {
            defer { isEndingSession = false }
            // Finish any writes from the cancelled sync before clearing vault data and keys.
            await pendingSync?.value
            await container.authRepo.lockVault()
            await container.vaultRepo.clearVault()
            // Clear all key caches in the same lock path as the vault store.
            // Key material must not outlive the vault session (Constitution §III).
            await container.vaultKeyCache.clear()
            await container.orgKeyCache.clear()
            vaultBrowserVM.clearDecryptedState()
            if let account = container.authRepo.storedAccount() {
                unlockVM = container.makeUnlockViewModel(account: account)
                screen = .unlock
            } else {
                screen = .login
            }
            logger.info("Vault locked")
        }
    }

    /// Whether the vault is currently unlocked (vault browser or sync in progress).
    var isVaultUnlocked: Bool {
        switch screen {
        case .vault, .syncing: return true
        default: return false
        }
    }

    func handleUnlockFlow(_ state: UnlockFlowState) {
        switch state {
        case .unlock:       screen = .unlock
        case .restoring:    screen = .loading
        case .loading:      screen = .unlock   // stay on unlock screen with spinner
        case .vault:        transitionToVault(caller: "handleUnlockFlow", syncOnEntry: true)
        case .login:
            // "Sign in with a different account" — reset to login.
            unlockVM = nil
            screen   = .login
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    // MARK: - Copy field from selected item

    enum CopyableField {
        case username, password, totp, website
    }

    func copySelectedField(_ field: CopyableField) {
        // Copy Code copies the *generated* code, never the stored seed (FR-016, FR-017).
        if field == .totp {
            Task { await copySelectedCode() }
            return
        }
        guard let value = selectedFieldValue(field) else { return }
        vaultBrowserVM.copy(value)
    }

    func selectedFieldAvailable(_ field: CopyableField) -> Bool {
        if field == .totp {
            guard let seed = selectedLogin?.totp else { return false }
            return (try? TOTPSeedParser.parse(seed)) != nil
        }
        return selectedFieldValue(field) != nil
    }

    /// Generates the current code for the selected Login and puts it on the clipboard through the
    /// shared path, so the 30-second auto-clear applies. Does nothing for an unusable seed.
    func copySelectedCode() async {
        guard let seed = selectedLogin?.totp, selectedFieldAvailable(.totp) else { return }
        do {
            let code = try await container.generateTOTPCode.execute(seed: seed, at: Date())
            vaultBrowserVM.copy(code.copyValue)
        } catch {
            // Never log the seed or the error payload (Constitution §III, §V).
            logger.error("Copy Code skipped: the stored seed is not usable")
        }
    }

    private func selectedFieldValue(_ field: CopyableField) -> String? {
        guard let login = selectedLogin else { return nil }

        switch field {
        case .username: return login.username
        case .password: return login.password
        case .website:  return login.uris.first?.uri
        case .totp:     return nil   // handled by copySelectedCode(); the seed is never copied
        }
    }
}
