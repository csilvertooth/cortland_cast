import Foundation

public struct Settings: Codable {
    public var port: Int = 7766
    var autoApply: Bool = false
    var openBrowser: Bool = true
    var confirmQuit: Bool = true
    var pollNowMs: Int = 1500
    var pollDevicesMs: Int = 3000
    var pollMasterMs: Int = 1500
    public var checkForUpdates: Bool = false
    var lastUpdateCheck: Double? = nil

    enum CodingKeys: String, CodingKey {
        case port
        case autoApply = "auto_apply"
        case openBrowser = "open_browser"
        case confirmQuit = "confirm_quit"
        case pollNowMs = "poll_now_ms"
        case pollDevicesMs = "poll_devices_ms"
        case pollMasterMs = "poll_master_ms"
        case checkForUpdates = "check_for_updates"
        case lastUpdateCheck = "last_update_check"
    }
}

let defaultSettings = Settings()
let configDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/CortlandCastServer")
let configPath = configDirectory.appendingPathComponent("config.json")

// For standalone executable, also check current directory
let currentDirSettingsPath = URL(fileURLWithPath: "./settings.json")

public class SettingsManager {
    public static let shared = SettingsManager()
    private var settings: Settings = defaultSettings
    private var currentConfigPath: URL = configPath // Track which config file we loaded

    private init() {
        load()
    }

    private func load() {
        // First try to load from Library directory (preferred location), then current directory
        let possiblePaths = [configPath, currentDirSettingsPath]

        for path in possiblePaths {
            do {
                let data = try Data(contentsOf: path)
                settings = try JSONDecoder().decode(Settings.self, from: data)
                currentConfigPath = path
                print("Loaded settings from: \(path.path)")
                return
            } catch {
                // Continue to try next path
            }
        }

        // If no config found, use defaults and save to Library directory
        settings = defaultSettings
        currentConfigPath = configPath
        save() // Try to create config.json in Library directory
    }

    private func save() {
        // Try to save to Library directory first (preferred), then fall back to current directory
        var savePaths = [configPath] // Library location first
        if currentConfigPath != configPath {
            savePaths.append(currentDirSettingsPath) // Current directory as fallback
        } else {
            savePaths.append(currentDirSettingsPath) // Always try current directory as fallback
        }

        for path in savePaths {
            do {
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                      withIntermediateDirectories: true)

                let data = try JSONEncoder().encode(settings)
                try data.write(to: path, options: .atomic)
                currentConfigPath = path
                print("Saved settings to: \(path.path)")
                return
            } catch {
                print("Failed to save to \(path.path): \(error)")
                // Continue to try next path
            }
        }

        print("Failed to save settings to any location")
    }

    public func get() -> Settings {
        return settings
    }

    public func update(_ newSettings: Settings) {
        settings = newSettings
        save()
    }
}
