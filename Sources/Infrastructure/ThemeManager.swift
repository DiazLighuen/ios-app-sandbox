import SwiftUI

final class ThemeManager: ObservableObject {
    @Published private(set) var appearance: String

    init() {
        appearance = UserDefaults.standard.string(forKey: "appAppearance") ?? "system"
    }

    func setAppearance(_ code: String) {
        UserDefaults.standard.set(code, forKey: "appAppearance")
        appearance = code
    }

    /// nil = follow system (passed to .preferredColorScheme)
    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
