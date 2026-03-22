import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authViewModel:   AuthViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var themeManager:    ThemeManager

    var body: some View {
        NavigationStack {
            List {
                // Account
                if let user = authViewModel.currentUser {
                    Section("settings.account".loc) {
                        HStack(spacing: 12) {
                            AsyncImage(url: user.avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(user.name).font(.headline)
                                    if user.isAdmin {
                                        Text("users.admin".loc)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundStyle(Color.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Appearance
                Section("settings.appearance".loc) {
                    Picker("settings.appearance".loc, selection: Binding(
                        get: { themeManager.appearance },
                        set: { themeManager.setAppearance($0) }
                    )) {
                        Text("settings.appearance.system".loc).tag("system")
                        Text("settings.appearance.light".loc).tag("light")
                        Text("settings.appearance.dark".loc).tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // Language
                Section("settings.language".loc) {
                    Picker("settings.language".loc, selection: Binding(
                        get: { languageManager.language },
                        set: { languageManager.setLanguage($0) }
                    )) {
                        ForEach(LanguageManager.supported, id: \.code) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Session
                Section("settings.session".loc) {
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        Label("settings.signOut".loc, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Info
                Section("settings.info".loc) {
                    let host = Bundle.main.object(forInfoDictionaryKey: "API_BASE_HOST") as? String ?? "localhost:8080"
                    LabeledContent("settings.backend".loc, value: host)
                    LabeledContent("settings.version".loc, value: "1.0.0")
                }
            }
            .navigationTitle("settings.title".loc)
        }
    }
}
