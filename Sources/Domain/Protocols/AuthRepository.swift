import Foundation

protocol AuthRepository {
    func loginWithGoogle(idToken: String) async throws -> String
    func linkYouTube(serverAuthCode: String) async throws
    func logout() async throws
}
