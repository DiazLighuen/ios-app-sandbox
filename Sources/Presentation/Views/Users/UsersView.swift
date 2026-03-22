import SwiftUI

struct UsersView: View {
    @StateObject private var viewModel = UsersViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showAddUser = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("loading".loc)
                } else if viewModel.users.isEmpty {
                    ContentUnavailableView(
                        "users.empty.title".loc,
                        systemImage: "person.2.slash",
                        description: Text("users.empty.desc".loc)
                    )
                } else {
                    List(viewModel.users) { user in
                        NavigationLink {
                            UserDetailView(user: user, viewModel: viewModel)
                        } label: {
                            UserRow(user: user)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("users.title".loc)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await viewModel.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddUser = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .alert("error".loc, isPresented: .constant(viewModel.error != nil)) {
                Button("ok".loc) { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showAddUser) {
            AddUserView { email, name, isAdmin in
                try await viewModel.createUser(email: email, name: name, isAdmin: isAdmin)
            }
        }
    }
}

private struct UserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(width: 44, height: 44).clipShape(Circle())
                default:
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(user.name.prefix(1).uppercased())
                                .font(.headline).foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name).font(.headline)
                    if user.isAdmin {
                        Text("users.admin".loc)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(user.email)
                    .font(.subheadline).foregroundStyle(.secondary)
                if let date = user.createdAt {
                    Text("\("users.created".loc): \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
