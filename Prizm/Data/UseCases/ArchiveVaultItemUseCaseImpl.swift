import Foundation

final class ArchiveVaultItemUseCaseImpl: ArchiveVaultItemUseCase {
    private let repository: any VaultRepository

    init(repository: any VaultRepository) {
        self.repository = repository
    }

    func execute(id: String, archived: Bool) async throws {
        try await repository.setArchived(id: id, archived: archived)
    }
}
