import Foundation

protocol AuthRepository {
    func loginWithGoogle(idToken: String) async throws -> String
    func logout() async throws
}
