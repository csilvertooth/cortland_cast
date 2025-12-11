import Foundation

public struct AppVersion: Codable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    public var stringValue: String {
        return "\(major).\(minor).\(patch)"
    }

    // Make it decodable from simple string like "1.0.0"
    init(string: String) throws {
        let components = string.split(separator: ".")
        guard components.count >= 3 else { throw URLError(.dataLengthExceedsMaximum) }

        guard let major = Int(String(components[0])),
              let minor = Int(String(components[1])),
              let patch = Int(String(components[2])) else {
            throw URLError(.dataLengthExceedsMaximum)
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(versionString: String) {
        let components = versionString.split(separator: ".")
        self.major = Int(components.first ?? "1") ?? 1
        self.minor = Int(components.dropFirst().first ?? "0") ?? 0
        self.patch = Int(components.dropFirst(2).first ?? "0") ?? 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
    }
}

// Current app version - update this when releasing
let currentVersion = AppVersion(versionString: "0.6.0")

public struct GitHubRelease: Codable {
    let tag_name: String
    let name: String
    let published_at: String
    let assets: [ReleaseAsset]
    let body: String?

    public var version: AppVersion {
        return AppVersion(versionString: tag_name.replacingOccurrences(of: "v", with: ""))
    }
}

struct ReleaseAsset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int

    var isMacArchive: Bool {
        return name.hasSuffix(".tar.gz") && (name.contains("macos") || name.contains("Mac") || name.contains("apple"))
    }
}

public class VersionManager {
    public static let shared = VersionManager()
    private let baseURL = "https://api.github.com/repos"
    private var currentCheckTask: Task<Void, Never>?

    // Cache for update info
    private var cachedRelease: GitHubRelease?
    private var lastCheckTime: Date?

    public func getCurrentVersion() -> AppVersion {
        return currentVersion
    }

    public func checkForUpdates() async -> GitHubRelease? {
        let settings = SettingsManager.shared.get()

        // Check if updates are enabled
        guard settings.checkForUpdates else {
            print("Update checking disabled")
            return nil
        }

        // Rate limit checks to once per hour
        if let lastCheck = lastCheckTime, Date().timeIntervalSince(lastCheck) < 3600 {
            return cachedRelease
        }

        // Cancel any existing check
        currentCheckTask?.cancel()
        currentCheckTask = nil

        // Update last check time
        lastCheckTime = Date()
        var updatedSettings = settings
        updatedSettings.lastUpdateCheck = Date().timeIntervalSince1970
        SettingsManager.shared.update(updatedSettings)

        do {
            let result = await performUpdateCheck()
            cachedRelease = result
            return result
        } catch {
            print("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func performUpdateCheck() async -> GitHubRelease? {
        // Check the actual public repo
        let repoPath = "csilvertooth/cortland_cast"
        let urlString = "\(baseURL)/\(repoPath)/releases/latest"

        print("Checking for updates at: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("Invalid GitHub URL")
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            if release.version > currentVersion {
                print("Update available! Current: \(currentVersion.stringValue), Latest: \(release.version.stringValue)")
                return release
            } else {
                print("No update available. Current: \(currentVersion.stringValue)")
                return nil
            }
        } catch {
            print("Failed to fetch release info: \(error.localizedDescription)")
            return nil
        }
    }

    func downloadAndInstallUpdate(_ release: GitHubRelease) async throws {
        guard let downloadAsset = release.assets.first(where: { $0.isMacArchive }) else {
            throw NSError(domain: "VersionManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No compatible download found for macOS"
            ])
        }

        print("Downloading: \(downloadAsset.browser_download_url)")
        print("This would trigger the download and installation process...")

        // In a real implementation, this would:
        // 1. Download the archive
        // 2. Extract it
        // 3. Replace the current executable
        // 4. Restart the app

        throw NSError(domain: "VersionManager", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Auto-update not implemented yet. Please manually download from GitHub releases."
        ])
    }

    func shouldPromptForUpdate(lastPromptDate: Date?, release: GitHubRelease) -> Bool {
        let settings = SettingsManager.shared.get()

        // Don't prompt if updates disabled
        guard settings.checkForUpdates else { return false }

        // Never prompted before
        guard let lastPrompt = lastPromptDate else { return true }

        // Only prompt once per release
        return Date().timeIntervalSince(lastPrompt) > 7 * 24 * 3600 // 7 days
    }
}
