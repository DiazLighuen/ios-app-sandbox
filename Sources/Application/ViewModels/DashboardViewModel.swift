import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var dashboard: DashboardData?
    @Published private(set) var isLoading = false
    @Published var error: AppError?

    private let repository: DashboardRepository

    init(repository: DashboardRepository = DashboardAPI()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await repository.fetchDashboard()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .networkError(error)
        }
    }
}
