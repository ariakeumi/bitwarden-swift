import SwiftUI
import os.log

// MARK: - VaultBrowserView

/// Three-pane vault browser using `NavigationSplitView`.
///
/// - Sidebar:  `SidebarView` (categories + counts)
/// - Content:  `ItemListView` with native search and `+` button
/// - Detail:   `ItemDetailView` with Edit / Delete buttons
struct VaultBrowserView: View {

    @ObservedObject var viewModel: VaultBrowserViewModel
    let faviconLoader: FaviconLoader
    let makeEditViewModel: (VaultItem) -> ItemEditViewModel
    let makeCreateViewModel: (ItemType, String?) -> ItemEditViewModel
    /// Factory for creating `AttachmentAddViewModel` — injected from AppContainer to
    /// keep the Presentation layer decoupled from the Data layer (Constitution §II).
    var makeAddAttachmentViewModel: ((String) -> AttachmentAddViewModel)? = nil
    /// Factory for creating `AttachmentBatchViewModel` — injected from AppContainer.
    var makeBatchAttachmentViewModel: ((String) -> AttachmentBatchViewModel)? = nil
    /// Factory for `AttachmentRowViewModel` — injected from AppContainer.
    var makeAttachmentRowViewModel: ((String, Attachment) -> AttachmentRowViewModel)? = nil
    /// Factory for the TOTP code tracker — injected from AppContainer (Constitution §II).
    var makeCodesViewModel: (() -> TOTPCodesViewModel)? = nil
    var isSyncing = false

    @State private var itemToArchive: VaultItem?
    @State private var showArchiveAlert = false
    @State private var showPermanentDeleteAlert = false
    @State private var showDeleteFolderAlert = false
    @State private var folderToDelete: Folder?
    @State private var isSearchFieldFocused = false
    @AppStorage("vault.layout.sidebarWidth") private var sidebarWidth = 210.0
    @AppStorage("vault.layout.itemListWidth") private var itemListWidth = 280.0
    @AppStorage("vault.layout.codesListWidth") private var codesListWidth = 420.0
    @AppStorage("vault.layout.columnVisibility") private var savedColumnVisibility = "all"
    @Environment(\.colorSchemeContrast) private var contrast

    private let logger = Logger(subsystem: "com.prizm", category: "UI.VaultBrowser")

    /// The middle column: Trash, Verification Codes, or the regular item list.
    /// Extracted from `body` to keep the type checker fast.
    @ViewBuilder
    private var itemListPane: some View {
        if viewModel.sidebarSelection == .trash {
            TrashView(
                items:             viewModel.displayedItems,
                selection:         $viewModel.itemSelection,
                faviconLoader:     faviconLoader,
                onRestore:         { id in await viewModel.performRestore(id: id) },
                onPermanentDelete: { id in await viewModel.performPermanentDelete(id: id) }
            )
        } else if viewModel.sidebarSelection == .verificationCodes, let makeCodesViewModel {
            VerificationCodesListView(
                items:         viewModel.displayedItems,
                selection:     $viewModel.itemSelection,
                faviconLoader: faviconLoader,
                searchQuery:   viewModel.searchQuery.isEmpty ? nil : viewModel.searchQuery,
                makeViewModel: makeCodesViewModel,
                onCopy:        { viewModel.copy($0) }
            )
        } else {
            ItemListView(
                items:          viewModel.displayedItems,
                selection:      $viewModel.itemSelection,
                faviconLoader:  faviconLoader,
                searchQuery:    viewModel.searchQuery.isEmpty ? nil : viewModel.searchQuery,
                organizations:  viewModel.organizations,
                onDelete:       { id in await viewModel.performSoftDelete(id: id) },
                isArchive:      viewModel.sidebarSelection == .archive,
                onArchive:      { requestArchive($0) },
                onToggleFavorite: { viewModel.toggleFavorite(item: $0) }
            )
        }
    }

    /// The detail column. Extracted from `body` to keep the type checker fast.
    private var itemDetail: some View {
        ItemDetailView(
            item:                           viewModel.itemSelection,
            faviconLoader:                  faviconLoader,
            folders:                        viewModel.folders,
            organizations:                  viewModel.organizations,
            onCopy:                         { viewModel.copy($0) },
            makeEditViewModel:              makeEditViewModel,
            makeAddAttachmentViewModel:     makeAddAttachmentViewModel,
            makeBatchAttachmentViewModel:   makeBatchAttachmentViewModel,
            makeAttachmentRowViewModel:     makeAttachmentRowViewModel,
            onAttachmentsChanged:           { viewModel.refreshItemSelection() },
            onEditSheetChanged:             { viewModel.handleEditSheetState($0) },
            onSoftDelete:                   { id in await viewModel.performSoftDelete(id: id) },
            onRestore:                      { id in await viewModel.performRestore(id: id) },
            onPermanentDelete:              { id in await viewModel.performPermanentDelete(id: id) },
            makeCodesViewModel:             makeCodesViewModel,
            editTrigger:                    viewModel.editTrigger,
            saveTrigger:                    viewModel.saveTrigger
        )
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: columnVisibility,
            sidebar: {
                VStack(spacing: 0) {
                    SidebarView(
                        selection: Binding(
                            get: { viewModel.isGlobalSearch ? nil : viewModel.sidebarSelection },
                            set: { newValue in
                                if let value = newValue {
                                    Task { @MainActor in viewModel.sidebarSelection = value }
                                }
                            }
                        ),
                        itemCounts: viewModel.itemCounts,
                        folders: viewModel.folders,
                        organizations: viewModel.organizations,
                        collections: viewModel.collections,
                        onCreateFolder: { name in viewModel.createFolder(name: name) },
                        onRenameFolder: { id, name in viewModel.renameFolder(id: id, name: name) },
                        onDeleteFolder: { folder in
                            folderToDelete = folder
                            showDeleteFolderAlert = true
                        },
                        onDropItems: { ids, folderId in viewModel.moveItemsToFolder(itemIds: ids, folderId: folderId) },
                        onCreateCollection: { name, orgId in viewModel.createCollection(name: name, organizationId: orgId) },
                        onRenameCollection: { id, orgId, name in viewModel.renameCollection(id: id, organizationId: orgId, name: name) },
                        onDeleteCollection: { id, orgId in viewModel.deleteCollection(id: id, organizationId: orgId) }
                    )
                    SyncStatusView(label: isSyncing ? String(localized: "Syncing vault…") : viewModel.syncStatusLabel)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: max(180, sidebarWidth))
                .onGeometryChange(for: Double.self) { geometry in
                    geometry.size.width.rounded()
                } action: { width in
                    if width >= 180 { sidebarWidth = width }
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        SettingsLink {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier(AccessibilityID.Vault.settingsButton)
                    }
                }
            },
            content: {
                VStack(spacing: 0) {
                    syncErrorBanner
                    itemListPane
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(ItemType.allCases) { type in
                                Button {
                                    viewModel.createItemType = type
                                } label: {
                                    Label(type.displayName, systemImage: type.sfSymbol)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("New Item (⌘N)")
                        .accessibilityLabel("New Item")
                        .accessibilityIdentifier(AccessibilityID.Create.newItemButton)
                        .menuIndicator(.visible)
                        .background {
                            Button("") { viewModel.createItemType = .login }
                                .keyboardShortcut("n", modifiers: .command)
                                .frame(width: 0, height: 0)
                                .opacity(0)
                        }
                    }
                }
                // The Verification Codes list shows name, code, countdown, and COPY on one line,
                // so it needs a wider column than the regular item list.
                .navigationSplitViewColumnWidth(
                    min:   viewModel.sidebarSelection == .verificationCodes ? 360 : 220,
                    ideal: viewModel.sidebarSelection == .verificationCodes
                        ? max(360, codesListWidth) : max(220, itemListWidth)
                )
                .onGeometryChange(for: Double.self) { geometry in
                    geometry.size.width.rounded()
                } action: { width in
                    if viewModel.sidebarSelection == .verificationCodes {
                        if width >= 360 { codesListWidth = width }
                    } else if width >= 220 {
                        itemListWidth = width
                    }
                }
            },
            detail: {
                itemDetail
                .toolbar {
                    if let item = viewModel.itemSelection {
                        if item.isDeleted {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Restore") {
                                    Task { await viewModel.performRestore(id: item.id) }
                                }
                                .accessibilityIdentifier(AccessibilityID.Trash.restoreButton)
                            }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("Delete Permanently", role: .destructive) {
                                    showPermanentDeleteAlert = true
                                }
                                .foregroundStyle(.red)
                                .accessibilityIdentifier(AccessibilityID.Trash.permanentDeleteButton)
                            }
                        } else {
                            ToolbarItem(placement: .primaryAction) {
                                Button(item.isArchived ? String(localized: "Unarchive") : String(localized: "Archive"), systemImage: "archivebox") {
                                    requestArchive(item)
                                }
                                .disabled(viewModel.editSheetOpen)
                                .accessibilityIdentifier("archive.toolbarAction")
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    viewModel.toggleFavorite(item: item)
                                } label: {
                                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                                }
                                .help(item.isFavorite ? "Unfavorite" : "Favorite")
                                .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite")
                                .accessibilityValue(item.isFavorite ? "Favorited" : "Not favorited")
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button("Edit") {
                                    viewModel.triggerEdit()
                                }
                                .disabled(viewModel.editSheetOpen)
                                .keyboardShortcut("e", modifiers: .command)
                                .accessibilityIdentifier(AccessibilityID.Edit.editButton)
                            }
                        }
                    }
                }
                .searchable(
                    text: $viewModel.searchQuery,
                    isPresented: $isSearchFieldFocused,
                    placement: .toolbar,
                    prompt: "Search vault"
                )
            }
        )
        .navigationSplitViewStyle(.balanced)
        .alert("Archive Item?", isPresented: $showArchiveAlert, presenting: itemToArchive) { item in
            Button("Archive") {
                Task { await viewModel.performArchive(id: item.id, archived: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("“\(item.name)” will move to Archive and be hidden from your active vault and verification codes.")
        }
        .alert("Action Failed", isPresented: Binding(
            get:  { viewModel.actionError != nil },
            set:  { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .alert("Delete Permanently?", isPresented: $showPermanentDeleteAlert) {
            Button("Delete Permanently", role: .destructive) {
                if let item = viewModel.itemSelection {
                    Task { await viewModel.performPermanentDelete(id: item.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(viewModel.itemSelection?.name ?? "")\" will be permanently deleted and cannot be recovered.")
        }
        .alert("Delete Folder?", isPresented: $showDeleteFolderAlert) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete {
                    viewModel.deleteFolder(id: folder.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items in \"\(folderToDelete?.name ?? "")\" will not be deleted. They will become unfoldered.")
        }
        .accessibilityIdentifier(AccessibilityID.Vault.navigationSplit)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onChange(of: viewModel.sidebarSelection) { _, newValue in
            if newValue == .trash {
                viewModel.searchQuery = ""
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            if newValue.isEmpty && viewModel.isGlobalSearch {
                viewModel.deactivateGlobalSearch()
            }
        }
        .onChange(of: viewModel.isGlobalSearch) { _, isActive in
            if !isActive { isSearchFieldFocused = false }
        }
        .onChange(of: viewModel.syncErrorMessage) { _, newMessage in
            if let message = newMessage {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: viewModel.actionError) { _, newError in
            if let error = newError {
                AccessibilityNotification.Announcement(error).post()
            }
        }
        .background {
            Button("") {
                viewModel.activateGlobalSearch()
                isSearchFieldFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .sheet(item: $viewModel.createItemType) { type in
            ItemEditView(
                viewModel: makeCreateViewModel(type,
                    viewModel.selectedCollectionId ?? viewModel.selectedFolderId),
                isPresented: Binding(
                    get: { viewModel.createItemType != nil },
                    set: { if !$0 { viewModel.createItemType = nil } }
                )
            )
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch savedColumnVisibility {
                case "detailOnly": .detailOnly
                case "doubleColumn": .doubleColumn
                default: .all
                }
            },
            set: { visibility in
                if visibility == .detailOnly {
                    savedColumnVisibility = "detailOnly"
                } else if visibility == .doubleColumn {
                    savedColumnVisibility = "doubleColumn"
                } else {
                    savedColumnVisibility = "all"
                }
            }
        )
    }

    private func requestArchive(_ item: VaultItem) {
        if item.isArchived {
            Task { await viewModel.performArchive(id: item.id, archived: false) }
        } else {
            itemToArchive = item
            showArchiveAlert = true
        }
    }

    // MARK: - Sync Error Banner

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let message = viewModel.syncErrorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(Typography.bannerText)
                Spacer()
                Button {
                    viewModel.dismissSyncError()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier(AccessibilityID.Vault.syncErrorDismiss)
            }
            .padding(.horizontal, Spacing.bannerHorizontal)
            .padding(.vertical, Spacing.bannerVertical)
            .background(Color.yellow.opacity(Opacity.bannerBackground(contrast)))
            .frame(maxHeight: 44)
            .accessibilityIdentifier(AccessibilityID.Vault.syncErrorBanner)
        }
    }
}
