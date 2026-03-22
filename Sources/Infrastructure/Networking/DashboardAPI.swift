import Foundation

final class DashboardAPI: DashboardRepository {
    private let client = HTTPClient.shared

    func fetchDashboard() async throws -> DashboardData {
        try await client.request("/api/dashboard")
    }
}
