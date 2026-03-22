import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var viewModel: UsersViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var actionError: String?

    private var isSelf: Bool {
        authViewModel.currentUser?.sub == user.id
    }
    private var isAdmin: Bool {
        authViewModel.currentUser?.isAdmin == true
    }

    var body: some View {
        List {
            // Avatar + identity
            Section("users.info".loc) {
                HStack(spacing: 14) {
                    AsyncImage(url: user.avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 60, height: 60).clipShape(Circle())
                        default:
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Text(user.name.prefix(1).uppercased())
                                        .font(.title2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
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
                        Text(user.email).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                if let date = user.createdAt {
                    LabeledContent("users.created".loc) {
                        Text(date.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Admin actions (only for admins, not on self)
            if isAdmin && !isSelf {
                Section("users.actions".loc) {
                    // Toggle admin
                    Button {
                        Task { await toggleAdmin() }
                    } label: {
                        Label(
                            user.isAdmin ? "users.admin.revoke".loc : "users.admin.grant".loc,
                            systemImage: user.isAdmin ? "person.badge.minus" : "person.badge.plus"
                        )
                    }
                    .disabled(viewModel.isProcessing)

                    // Delete
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("users.delete".loc, systemImage: "trash")
                    }
                    .disabled(viewModel.isProcessing)
                }
            } else if isSelf {
                Section {
                    Label("users.noSelf".loc, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isProcessing {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "users.delete".loc,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("users.delete.confirm".loc, role: .destructive) {
                Task { await deleteUser() }
            }
            Button("cancel".loc, role: .cancel) {}
        } message: {
            Text("users.delete.message".loc)
        }
        .alert("error".loc, isPresented: .constant(actionError != nil)) {
            Button("ok".loc) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Actions

    private func toggleAdmin() async {
        do {
            try await viewModel.setAdminStatus(id: user.id, isAdmin: !user.isAdmin)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteUser() async {
        do {
            try await viewModel.deleteUser(id: user.id)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
