import Foundation

final class AuthAPI: AuthRepository {
    private let client = HTTPClient.shared

    func loginWithGoogle(idToken: String) async throws -> String {
        let body = GoogleLoginRequest(idToken: idToken)
        let response: LoginResponse = try await client.request(
            "/auth/google/mobile",
            method: "POST",
            body: body,
            authenticated: false
        )
        return response.token
    }

    func logout() async throws {}
}

private struct GoogleLoginRequest: Encodable {
    let idToken: String
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

// Respuesta completa del backend: { "token": "...", "user": { ... } }
private struct LoginResponse: Decodable {
    let token: String
}
