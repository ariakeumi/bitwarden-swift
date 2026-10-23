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
/// Each row has a context menu with a "Delete" action that moves the item to Trash.
struct ItemListView: View {

    let items:         [VaultItem]
    @Binding var selection: VaultItem?
    let faviconLoader: FaviconLoader
    var searchQuery:   String? = nil
    /// Organizations list for resolving org names shown on item rows (6.1).
    var organizations: [Organization] = []
    /// Called when the user confirms moving an item to Trash from the row context menu.
    /// Nil disables the delete context-menu action (e.g. when trash actions are unavailable).
    var onDelete: ((String) async -> Void)? = nil
    var isArchive: Bool = false
    var onArchive: ((VaultItem) -> Void)? = nil
    var onToggleFavorite: ((VaultItem) -> Void)? = nil

    // Tracks which item is pending a soft-delete confirmation alert.
    @State private var itemToDelete:    VaultItem? = nil
    @State private var showDeleteAlert: Bool       = false
    @FocusState private var isListFocused: Bool
    @State private var didFocusList = false
    @AppStorage("vault.list.sortOrder") private var sortOrder: ItemListSortOrder = .nameAscending

    private var sections: [(letter: String?, items: [VaultItem])] {
        sortOrder.sections(for: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(ItemListSortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .fixedSize()
                .help("Sort items")
                .accessibilityLabel("Sort items")
                .accessibilityValue(sortOrder.title)
                .accessibilityIdentifier(AccessibilityID.ItemList.sortMenu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

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
                                    .tag(item)
                                    .draggable(item.id)
                                    .accessibilityIdentifier(AccessibilityID.ItemList.row(item.id))
                                    .contextMenu {
                                        if let onToggleFavorite {
                                            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                                onToggleFavorite(item)
                                            }
                                        }
                                        if let onArchive {
                                            Button(item.isArchived ? String(localized: "Unarchive") : String(localized: "Archive")) {
                                                onArchive(item)
                                            }
                                            .accessibilityIdentifier("archive.contextAction")
                                        }
                                        if onDelete != nil {
                                            Button("Delete", role: .destructive) {
                                                itemToDelete    = item
                                                showDeleteAlert = true
                                            }
                                        }
                                    }
                            }
                        } header: {
                            if let letter = section.letter {
                                Text(letter)
                                    .accessibilityAddTraits(.isHeader)
                            }
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
                // Soft-delete confirmation alert — shown when the user selects "Delete"
                // from a row context menu. The item is only moved to Trash, not permanently
                // deleted; it can be recovered from the Trash view.
                .alert(
                    "Move to Trash?",
                    isPresented: $showDeleteAlert,
                    presenting:  itemToDelete
                ) { item in
                    Button("Move to Trash", role: .destructive) {
                        Task { await onDelete?(item.id) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { item in
                    Text("\"\(item.name)\" will be moved to Trash.")
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
