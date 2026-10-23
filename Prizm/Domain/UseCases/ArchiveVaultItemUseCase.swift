import Foundation

/// Changes only the current user's archive state; other organization members are unaffected.
protocol ArchiveVaultItemUseCase: AnyObject {
    func execute(id: String, archived: Bool) async throws
}
