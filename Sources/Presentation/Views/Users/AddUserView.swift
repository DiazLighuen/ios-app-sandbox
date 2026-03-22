import SwiftUI

struct AddUserView: View {
    let onCreate: (String, String?, Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email    = ""
    @State private var name     = ""
    @State private var isAdmin  = false
    @State private var isSaving = false
    @State private var error: String?

    private var isValid: Bool { !email.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("users.email".loc) {
                    TextField("users.email".loc, text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("users.name".loc) {
                    TextField("users.name.optional".loc, text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Toggle("users.grantAdmin".loc, isOn: $isAdmin)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("users.add".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".loc) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".loc) {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func save() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)
        isSaving = true
        defer { isSaving = false }
        do {
            try await onCreate(
                trimmedEmail,
                trimmedName.isEmpty ? nil : trimmedName,
                isAdmin
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
