import Foundation

struct User: Identifiable, Decodable {
    let id: UUID
    let email: String
    let name: String
    let avatarURL: URL?
    let isAdmin: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case avatarURL = "avatar"     // backend sends "avatar", not "avatar_url"
        case isAdmin   = "is_admin"
        case createdAt = "created_at"
    }
}

// MARK: - Decodable (custom date parsing)
extension User {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        email     = try c.decode(String.self, forKey: .email)
        name      = try c.decode(String.self, forKey: .name)
        isAdmin   = try c.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        avatarURL = try c.decodeIfPresent(URL.self,  forKey: .avatarURL)

        if let raw = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Self.parseDate(raw)
        } else {
            createdAt = nil
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}
