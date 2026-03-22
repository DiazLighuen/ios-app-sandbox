import Foundation

final class UsersAPI: UsersRepository {
    private let client = HTTPClient.shared

    func fetchUsers() async throws -> [User] {
        try await client.request("/api/users")
    }

    // POST /api/users returns {"ok":true,"email":"..."} — not a User object.
    // The ViewModel reloads the list after this call to pick up the new user.
    func createUser(email: String, name: String?, isAdmin: Bool) async throws {
        struct Body: Encodable {
            let email: String
            let name: String?
            let is_admin: Bool
        }
        try await client.requestVoid(
            "/api/users",
            method: "POST",
            body: Body(email: email, name: name, is_admin: isAdmin)
        )
    }

    func deleteUser(id: UUID) async throws {
        try await client.requestVoid("/api/users/\(id.uuidString.lowercased())", method: "DELETE")
    }

    func setAdminStatus(id: UUID, isAdmin: Bool) async throws {
        struct Body: Encodable { let is_admin: Bool }
        try await client.requestVoid(
            "/api/users/\(id.uuidString.lowercased())",
            method: "PATCH",
            body: Body(is_admin: isAdmin)
        )
    }
}
