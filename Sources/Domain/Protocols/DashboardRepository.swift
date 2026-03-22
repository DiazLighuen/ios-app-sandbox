import Foundation

protocol DashboardRepository {
    func fetchDashboard() async throws -> DashboardData
}
