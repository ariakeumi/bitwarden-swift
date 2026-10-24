import SwiftUI

enum ItemListSortOrder: String, CaseIterable {
    case nameAscending
    case nameDescending
    case recentlyModified
    case recentlyCreated

    var title: String {
        switch self {
        case .nameAscending: String(localized: "Name (A–Z)")
        case .nameDescending: String(localized: "Name (Z–A)")
        case .recentlyModified: String(localized: "Recently Modified")
        case .recentlyCreated: String(localized: "Recently Created")
        }
    }

    func sections(for items: [VaultItem]) -> [(letter: String?, items: [VaultItem])] {
        let sorted = items.sorted { lhs, rhs in
            switch self {
            case .recentlyModified where lhs.revisionDate != rhs.revisionDate:
                return lhs.revisionDate > rhs.revisionDate
            case .recentlyCreated where lhs.creationDate != rhs.creationDate:
                return lhs.creationDate > rhs.creationDate
            default:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison == .orderedSame { return lhs.id < rhs.id }
                return self == .nameDescending ? comparison == .orderedDescending : comparison == .orderedAscending
            }
        }

        // Time-based ordering must span the entire list, without letter groups.
        guard self == .nameAscending || self == .nameDescending else {
            return sorted.isEmpty ? [] : [(letter: nil, items: sorted)]
        }
        let grouped = Dictionary(grouping: sorted) { item in
            let first = item.name.first.map { String($0).uppercased() } ?? "#"
            return first.first?.isLetter == true ? first : "#"
        }
        return grouped.sorted { lhs, rhs in
            if lhs.key == "#" { return false }
            if rhs.key == "#" { return true }
            let comparison = lhs.key.localizedStandardCompare(rhs.key)
            return self == .nameDescending ? comparison == .orderedDescending : comparison == .orderedAscending
        }.map { (letter: $0.key, items: $0.value) }
    }
}

// MARK: - ItemListView

/// Middle-column list of vault items for the currently selected sidebar category (FR-040).
///
/// Items are sorted locally using the user's saved preference.
/// An empty state message is shown when the list is empty (FR-042).
/// Native multi-selection and context menus share stable IDs across syncs and edits.
struct ItemListView: View {

    let items:         [VaultItem]
    @Binding var selection: Set<String>
    let faviconLoader: FaviconLoader
    @Binding var sortOrder: ItemListSortOrder
    var searchQuery:   String? = nil
    /// Organizations list for resolving org names shown on item rows (6.1).
    var organizations: [Organization] = []
    /// Called when the user confirms moving the contextual selection to Trash.
    /// Nil disables the delete context-menu action (e.g. when trash actions are unavailable).
    var onDelete: (([String]) async -> Void)? = nil
    var isArchive: Bool = false
    var onArchive: (([VaultItem]) -> Void)? = nil
    var onToggleFavorite: ((VaultItem) -> Void)? = nil

    // Snapshot the full contextual selection before showing confirmation.
    @State private var itemIDsToDelete: [String] = []
    @State private var itemNameToDelete: String?
    @State private var showDeleteAlert: Bool       = false
    @FocusState private var isListFocused: Bool
    @State private var didFocusList = false

    private var sections: [(letter: String?, items: [VaultItem])] {
        sortOrder.sections(for: items)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(isArchive ? String(localized: "No Archived Items") : String(localized: "No Items"),
                          systemImage: isArchive ? "archivebox" : "tray")
                } description: {
                    Text(isArchive ? String(localized: "Archived items will appear here.") : String(localized: "No items in this category."))
                }
                .accessibilityIdentifier(AccessibilityID.ItemList.emptyState)
            } else {
                List(selection: $selection) {
                    ForEach(sections, id: \.letter) { section in
                        Section {
                            ForEach(section.items, id: \.id) { item in
                                ItemRowView(item: item, faviconLoader: faviconLoader, searchQuery: searchQuery,
                                            orgName: orgName(for: item))
                                    .tag(item.id)
                                    .draggable(item.id)
                                    .accessibilityIdentifier(AccessibilityID.ItemList.row(item.id))
                            }
                        } header: {
                            if let letter = section.letter {
                                Text(letter)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let contextualItems = items.filter { ids.contains($0.id) }
                    if let item = contextualItems.first {
                        if contextualItems.count == 1, let onToggleFavorite {
                            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                onToggleFavorite(item)
                            }
                        }
                        if let onArchive {
                            Button(isArchive ? String(localized: "Unarchive") : String(localized: "Archive")) {
                                onArchive(contextualItems)
                            }
                            .accessibilityIdentifier("archive.contextAction")
                        }
                        if onDelete != nil {
                            Button("Delete", role: .destructive) {
                                itemIDsToDelete = contextualItems.map(\.id)
                                itemNameToDelete = contextualItems.count == 1 ? item.name : nil
                                showDeleteAlert = true
                            }
                            .accessibilityIdentifier("itemList.deleteAction")
                        }
                    }
                }
                .focused($isListFocused)
                .task {
                    // The populated list can appear after the initial vault sync.
                    // Do not reclaim focus when a search temporarily empties the list.
                    guard !didFocusList else { return }
                    didFocusList = true
                    isListFocused = true
                }
                .alert("Move to Trash?", isPresented: $showDeleteAlert) {
                    Button("Move to Trash", role: .destructive) {
                        let ids = itemIDsToDelete
                        Task { await onDelete?(ids) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if let name = itemNameToDelete {
                        Text("\"\(name)\" will be moved to Trash.")
                    } else {
                        Text("\(itemIDsToDelete.count) items will be moved to Trash.")
                    }
                }
            }
        }
    }

    /// Returns the org name for a vault item, or nil for personal items.
    private func orgName(for item: VaultItem) -> String? {
        guard let orgId = item.organizationId else { return nil }
        return organizations.first(where: { $0.id == orgId })?.name
    }
}
