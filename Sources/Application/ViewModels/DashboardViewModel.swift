import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var dashboard: DashboardData?
    @Published private(set) var isLoading = false
    @Published private(set) var togglingContainers: Set<String> = []
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

    func toggleContainer(_ container: ContainerInfo) async {
        guard !togglingContainers.contains(container.name) else { return }
        let action = container.running ? "stop" : "start"
        togglingContainers.insert(container.name)
        defer { togglingContainers.remove(container.name) }
        do {
            _ = try await repository.toggleContainer(name: container.name, action: action)
            dashboard = try await repository.fetchDashboard()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .networkError(error)
        }
    }
}
