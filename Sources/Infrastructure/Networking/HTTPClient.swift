import Foundation

final class HTTPClient {
    static let shared = HTTPClient()
    let baseURL: URL = {
        let host = AppConfig.apiHost
        let scheme = host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") ? "http" : "https"
        return URL(string: "\(scheme)://\(host)")!
    }()
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true,
        autoLogout: Bool = true,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        var urlRequest = URLRequest(url: URL(string: baseURL.absoluteString + path)!)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = try KeychainService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("🔴 Decoding error en \(urlRequest.url?.path ?? "?"):")
                print("   Error:", error)
                print("   Raw JSON:", rawBody)
                throw AppError.decodingError(error)
            }
        case 401:
            if autoLogout {
                NotificationCenter.default.post(name: .didReceiveUnauthorized, object: nil)
            }
            throw AppError.unauthorized
        case 403:
            let msg = (try? decoder.decode(ServerErrorResponse.self, from: data))?.message ?? rawBody
            throw AppError.serverError("403 – \(msg.isEmpty ? "Forbidden" : msg)")
        default:
            let serverError = try? decoder.decode(ServerErrorResponse.self, from: data)
            throw AppError.serverError(serverError?.message ?? "HTTP \(http.statusCode): \(rawBody)")
        }
    }

    /// For requests that return no meaningful body (POST with {ok:true}, DELETE, PATCH, etc.)
    /// autoLogout defaults to false — a single failed mutation should not log the user out.
    func requestVoid(
        _ path: String,
        method: String = "DELETE",
        body: Encodable? = nil,
        authenticated: Bool = true,
        autoLogout: Bool = false,
        additionalHeaders: [String: String] = [:]
    ) async throws {
        var urlRequest = URLRequest(url: URL(string: baseURL.absoluteString + path)!)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = try KeychainService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body { urlRequest.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AppError.unknown }
        let rawBody = String(data: data, encoding: .utf8) ?? ""

        switch http.statusCode {
        case 200...299: return
        case 401:
            if autoLogout {
                NotificationCenter.default.post(name: .didReceiveUnauthorized, object: nil)
            }
            throw AppError.unauthorized
        case 403:
            let msg = (try? decoder.decode(ServerErrorResponse.self, from: data))?.message ?? rawBody
            throw AppError.serverError("403 – \(msg)")
        default:
            let serverError = try? decoder.decode(ServerErrorResponse.self, from: data)
            throw AppError.serverError(serverError?.message ?? "HTTP \(http.statusCode): \(rawBody)")
        }
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String?
    let detail: String?
    var message: String { error ?? detail ?? "" }
}
