import Foundation

final class DashboardAPI: DashboardRepository {
    private let client = HTTPClient.shared

    func fetchDashboard() async throws -> DashboardData {
        try await client.request("/api/dashboard")
    }

    func toggleContainer(name: String, action: String) async throws -> ToggleResult {
        try await client.request("/api/containers/\(name)/\(action)", method: "POST")
    }
}
