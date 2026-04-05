import Foundation

// MARK: - UserDefault Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    let userDefaults: UserDefaults

    init(key: String, defaultValue: T, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults
    }

    var wrappedValue: T {
        get {
            userDefaults.object(forKey: key) as? T ?? defaultValue
        }
        set {
            userDefaults.set(newValue, forKey: key)
        }
    }
}

// MARK: - Settings Manager

@MainActor
final class Settings {
    static let shared = Settings()

    @UserDefault(key: "autoPlayOnLaunch", defaultValue: true)
    var autoPlayOnLaunch: Bool

    @UserDefault(key: "volume", defaultValue: 0.8)
    var volume: Float

    @UserDefault(key: "lastPlayedChannelId", defaultValue: nil)
    var lastPlayedChannelId: String?

    @UserDefault(key: "menuShowsListenerCount", defaultValue: true)
    var menuShowsListenerCount: Bool

    private init() {}
}
