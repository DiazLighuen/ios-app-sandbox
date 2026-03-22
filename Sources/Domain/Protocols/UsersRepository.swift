import Foundation

protocol UsersRepository {
    func fetchUsers() async throws -> [User]
    func createUser(email: String, name: String?, isAdmin: Bool) async throws
    func deleteUser(id: UUID) async throws
    func setAdminStatus(id: UUID, isAdmin: Bool) async throws
}
