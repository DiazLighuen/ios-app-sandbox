import Foundation

struct CurrentUser {
    let sub: UUID
    let email: String
    let name: String
    let avatarURL: URL?
    let isAdmin: Bool

    /// Decodifica el usuario directamente del payload del JWT almacenado en Keychain.
    static func from(jwt: String) -> CurrentUser? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2,
              let data = Data(base64Encoded: String(parts[1]).jwtPadded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let subStr = json["sub"] as? String,
              let sub    = UUID(uuidString: subStr),
              let email  = json["email"] as? String,
              let name   = json["name"] as? String
        else { return nil }

        return CurrentUser(
            sub:       sub,
            email:     email,
            name:      name,
            avatarURL: (json["avatar"] as? String).flatMap(URL.init),
            isAdmin:   json["is_admin"] as? Bool ?? false
        )
    }
}

extension String {
    /// Padding necesario para decodificar base64url (JWT usa base64 sin padding).
    var jwtPadded: String {
        let r = count % 4
        return r == 0 ? self : self + String(repeating: "=", count: 4 - r)
    }
}
