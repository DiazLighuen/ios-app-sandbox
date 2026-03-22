import Foundation

final class LanguageManager: ObservableObject {
    @Published private(set) var language: String

    static let supported: [(code: String, label: String)] = [
        ("en", "English"),
        ("es", "Español"),
        ("de", "Deutsch"),
    ]

    var bundle: Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init) ?? .main
    }

    init() {
        language = UserDefaults.standard.string(forKey: "appLanguage") ?? "es"
    }

    func setLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "appLanguage")
        language = code
    }
}

// MARK: - String helper

extension String {
    /// Returns the localized string for the current app language.
    var loc: String {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "es"
        guard
            let path   = Bundle.main.path(forResource: lang, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return self }
        return bundle.localizedString(forKey: self, value: self, table: nil)
    }
}
