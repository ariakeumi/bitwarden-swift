import XCTest
@testable import Prizm

@MainActor
final class ItemListSortOrderTests: XCTestCase {
    func testNameSortingUsesNaturalOrderAndReversesSections() {
        let items = [item("b", "Beta"), item("10", "Account 10"), item("2", "account 2")]

        let ascending = ItemListSortOrder.nameAscending.sections(for: items)
        XCTAssertEqual(ascending.compactMap(\.letter), ["A", "B"])
        XCTAssertEqual(ascending.flatMap(\.items).map(\.id), ["2", "10", "b"])

        let descending = ItemListSortOrder.nameDescending.sections(for: items)
        XCTAssertEqual(descending.compactMap(\.letter), ["B", "A"])
        XCTAssertEqual(descending.flatMap(\.items).map(\.id), ["b", "10", "2"])
    }

    func testDateSortingOrdersAcrossLettersWithoutAlphabeticalSections() {
        let items = [
            item("a", "Alpha", created: 30, modified: 10),
            item("z", "Zulu", created: 10, modified: 30),
            item("b", "Beta", created: 20, modified: 20)
        ]

        let modified = ItemListSortOrder.recentlyModified.sections(for: items)
        XCTAssertEqual(modified.count, 1)
        XCTAssertNil(modified.first?.letter)
        XCTAssertEqual(modified.flatMap(\.items).map(\.id), ["z", "b", "a"])

        let created = ItemListSortOrder.recentlyCreated.sections(for: items)
        XCTAssertNil(created.first?.letter)
        XCTAssertEqual(created.flatMap(\.items).map(\.id), ["a", "b", "z"])
    }

    func testEqualDatesAndNamesHaveStableOrder() {
        let items = [item("2", "Alpha"), item("z", "Zulu"), item("1", "Alpha")]

        for order in [ItemListSortOrder.recentlyCreated, .recentlyModified] {
            XCTAssertEqual(order.sections(for: items).flatMap(\.items).map(\.id), ["1", "2", "z"])
        }
    }

    func testNonLetterNamesStayInLastSectionInEitherNameDirection() {
        let items = [item("empty", ""), item("a", "Alpha"), item("number", "123")]

        for order in [ItemListSortOrder.nameAscending, .nameDescending] {
            let sections = order.sections(for: items)
            XCTAssertEqual(sections.compactMap(\.letter), ["A", "#"])
            XCTAssertEqual(Set(sections.last!.items.map(\.id)), ["empty", "number"])
        }
    }

    func testEmptyListRemainsEmptyForEveryOrder() {
        for order in ItemListSortOrder.allCases {
            XCTAssertTrue(order.sections(for: []).flatMap(\.items).isEmpty)
        }
    }

    private func item(_ id: String, _ name: String, created: TimeInterval = 0, modified: TimeInterval = 0) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: Date(timeIntervalSince1970: created),
            revisionDate: Date(timeIntervalSince1970: modified),
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }
}
