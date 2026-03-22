import Foundation

@MainActor
final class UsersViewModel: ObservableObject {
    @Published private(set) var users: [User] = []
    @Published private(set) var isLoading    = false
    @Published private(set) var isProcessing = false
    @Published var error: AppError?

    private let repository: UsersRepository

    init(repository: UsersRepository = UsersAPI()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await repository.fetchUsers()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .networkError(error)
        }
    }

    func createUser(email: String, name: String?, isAdmin: Bool) async throws {
        isProcessing = true
        defer { isProcessing = false }
        try await repository.createUser(email: email, name: name, isAdmin: isAdmin)
        // POST returns {ok:true}, not a User — reload the full list to get the new entry
        users = (try? await repository.fetchUsers()) ?? users
    }

    func deleteUser(id: UUID) async throws {
        isProcessing = true
        defer { isProcessing = false }
        try await repository.deleteUser(id: id)
        users.removeAll { $0.id == id }
    }

    func setAdminStatus(id: UUID, isAdmin: Bool) async throws {
        isProcessing = true
        defer { isProcessing = false }
        try await repository.setAdminStatus(id: id, isAdmin: isAdmin)
        // Reflect change locally while we reload in background
        if let idx = users.firstIndex(where: { $0.id == id }) {
            let old = users[idx]
            users[idx] = User(
                id: old.id, email: old.email, name: old.name,
                avatarURL: old.avatarURL, isAdmin: isAdmin, createdAt: old.createdAt
            )
        }
    }
}
