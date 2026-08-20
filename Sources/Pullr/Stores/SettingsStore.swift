import Foundation

final class SettingsStore {
    private let key: String
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(key: String = "Pullr.AppSettings", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        return (try? decoder.decode(AppSettings.self, from: data)) ?? .default
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() -> AppSettings {
        defaults.removeObject(forKey: key)
        return .default
    }
}
