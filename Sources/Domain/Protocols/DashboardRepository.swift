import Foundation

protocol DashboardRepository {
    func fetchDashboard() async throws -> DashboardData
    func toggleContainer(name: String, action: String) async throws -> ToggleResult
}
