import Foundation

/// Fetches the encrypted vault from the server and populates the in-memory store.
/// Called after login, after unlock, and for user-requested sync.
protocol SyncUseCase {
    func execute(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult
}
