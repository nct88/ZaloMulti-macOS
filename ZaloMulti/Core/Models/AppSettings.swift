import Foundation

struct AppSettings: Codable {
    var theme: String = "system"
    var accentColor: String = "#0068FF"
    var profileRoot: String?
    var maxClones: Int = 10
    var autoLaunchOnStartup: Bool = false
    var showMenuBarIcon: Bool = true
    var checkUpdateOnStartup: Bool = true
}

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let key = "app_settings_v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func reset() {
        settings = AppSettings()
    }
}
