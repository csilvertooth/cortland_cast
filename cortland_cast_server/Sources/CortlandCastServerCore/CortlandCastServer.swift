// Cortland Cast Server - Core Implementation
// Copyright © 2025 Chris Silvertooth. All rights reserved.

import Vapor
import ScriptingBridge
import MusicKit

// Struct definitions for API requests/responses
struct MySettings: Content {
    let port: Int
    let open_browser: Bool
}

struct Device: Content {
    let id: Int
    let name: String
    let volume: Int
}

struct ShuffleRequest: Content {
    let enabled: Bool
}

struct RepeatRequest: Content {
    let mode: String
}

struct VolumeRequest: Content {
    let volume: Int
}

struct VolumeResponse: Content {
    let success: Bool
    let volume: Int
}

struct SeekRequest: Content {
    let position: Double
}

struct PlaylistTracksResponse: Content {
    let tracks: [String]
    let truncated: Bool
    let total: Int
    let limit: Int?
    let message: String?
    let error: String?
}

struct PlayRequest: Content {
    let type: String?
    let name: String?
    let album: String?
    let shuffle: Bool?
}

struct AirPlayDevice: Content {
    let id: String
    let name: String
    let active: Bool
    let volume: Int
    let kind: String
    let available: Bool
}

struct AirPlayDeviceStatus: Hashable {
    let id: String
    let selected: Bool
    let volume: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(selected)
        hasher.combine(volume)
    }
}

struct AirPlaySetActiveRequest: Content {
    let device_ids: [String]
}

struct AirPlayVolumeRequest: Content {
    let device_id: String
    let volume: Int
}

// Real-time state change monitoring structures

// Current state snapshot for events endpoint
struct EventSnapshot: Content {
    let player_state: String
    let shuffle_enabled: Bool
    let repeat_mode: String
    let volume: Int
}

// Thread-safe state tracker
actor StateTracker {
    private var lastStates: [String: Any] = [:]

    func hasChanged(_ key: String, newValue: Any) -> Bool {
        let oldValue = lastStates[key]

        // Simple comparison - could be enhanced
        if let oldNum = oldValue as? NSNumber, let newNum = newValue as? NSNumber {
            if oldNum.doubleValue != newNum.doubleValue { return true }
        } else if let oldStr = oldValue as? String, let newStr = newValue as? String {
            if oldStr != newStr { return true }
        } else {
            // For other types, assume changed if different
            return true
        }

        lastStates[key] = newValue
        return false
    }

    func updateState(_ key: String, value: Any) {
        lastStates[key] = value
    }

    func getState(_ key: String) -> Any? {
        return lastStates[key]
    }
}

// Real-time state change monitoring structures
struct StateChange {
    let type: String  // "now_playing", "volume", "shuffle", "repeat", "playback_state", "airplay_devices"
    let data: [String: Any]

func escapeJSONString(_ str: String) -> String {
    var result = str
    result = result.replacingOccurrences(of: "\\", with: "\\\\")
    result = result.replacingOccurrences(of: "\"", with: "\\\"")
    result = result.replacingOccurrences(of: "\n", with: "\\n")
    result = result.replacingOccurrences(of: "\r", with: "\\r")
    result = result.replacingOccurrences(of: "\t", with: "\\t")
    return result
}

    var json: String {
        // Use proper JSON escaping for all fields
        switch type {
        case "now_playing":
            let state = escapeJSONString(data["state"] as? String ?? "unknown")
            let title = escapeJSONString(data["title"] as? String ?? "")
            let artist = escapeJSONString(data["artist"] as? String ?? "")
            let album = escapeJSONString(data["album"] as? String ?? "")
            let position = data["position"] as? Double ?? 0.0
            let volume = data["volume"] as? Int ?? 0
            let isPlaying = data["is_playing"] as? Bool ?? false
            return "{\"state\": \"\(state)\", \"title\": \"\(title)\", \"artist\": \"\(artist)\", \"album\": \"\(album)\", \"position\": \(position), \"volume\": \(volume), \"is_playing\": \(isPlaying)}"

        case "position":
            let position = data["position"] as? Double ?? 0.0
            return "{\"position\": \(position)}"

        case "volume":
            let volume = data["volume"] as? Int ?? 0
            return "{\"volume\": \(volume)}"

        case "playback_state":
            let state = escapeJSONString(data["state"] as? String ?? "idle")
            return "{\"state\": \"\(state)\"}"

        case "repeat":
            let mode = escapeJSONString(data["mode"] as? String ?? "off")
            return "{\"mode\": \"\(mode)\"}"

        case "shuffle":
            let enabled = data["enabled"] as? Bool ?? false
            return "{\"enabled\": \(enabled)}"

        case "airplay_devices":
            if let devices = data["devices"] as? [[String: Any]] {
                var deviceStrings: [String] = []
                for device in devices {
                    if let id = device["id"] as? String,
                       let name = device["name"] as? String,
                       let active = device["active"] as? Bool,
                       let volume = device["volume"] as? Int,
                       let kind = device["kind"] as? String {
                        let deviceStr = "{\"id\": \"\(escapeJSONString(id))\", \"name\": \"\(escapeJSONString(name))\", \"active\": \(active), \"volume\": \(volume), \"kind\": \"\(escapeJSONString(kind))\"}"
                        deviceStrings.append(deviceStr)
                    }
                }
                return "{\"devices\": [\(deviceStrings.joined(separator: ", "))]}"
            }
            return "{\"devices\": []}"

        default:
            return "{\"unknown\": true}"
        }
    }
}

// Global state tracker
let stateTracker = StateTracker()

public class MusicServer {
    private var app: Application?
    private var runningTask: Task<Void, Never>?
    private var stopRequested = false  // Direct flag to stop the server
    public private(set) var port: Int = 7766

    public init() {}

    public func start(port: Int = 7766) async throws {
        guard runningTask == nil, !stopRequested else { return }

        self.port = port
        self.stopRequested = false

        // Ensure directories exist
        let _ = getArtworkCacheDirectory()

        // Create a new task that will run the server
        runningTask = Task {
            do {
                self.app = try await Application.make(.development)

                // Load settings for port configuration
                var settings = SettingsManager.shared.get()
                settings.port = port
                SettingsManager.shared.update(settings)

                // Configure server to listen on all interfaces
                app?.http.server.configuration.hostname = "0.0.0.0"
                app?.http.server.configuration.port = port

                // Add routes
                try self.routes(self.app!)

                print("Starting server on port \(port)...")
                try await app?.start()

                print("Server started successfully")

                // Server is now running - monitor for stop request
                while !self.stopRequested {
                    try? await Task.sleep(nanoseconds: 100_000_000) // Brief pause to prevent busy waiting
                }

                print("Server stop detected, initiating shutdown...")
                await self.app?.shutdown()

            } catch {
                print("Server error: \(error)")
            }

            // Clean up when task ends
            print("Server task completed")
            self.app = nil
            self.runningTask = nil
            self.stopRequested = false
        }

        // Give the server a moment to start
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
    }

    public func stop() async {
        guard runningTask != nil else { return }

        print("Stopping server...")
        stopRequested = true

        // Wait for the server task to complete (it will shutdown when stopRequested is detected)
        await runningTask?.value

        print("Server stop command completed")
    }

    public var running: Bool {
        return runningTask != nil && !runningTask!.isCancelled && !stopRequested
    }

    // Routes exactly matching App.swift - only artwork cache directory changed
    private func routes(_ app: Application) throws {
        // Root redirect
        app.get("") { req in
            return req.redirect(to: "/ui", redirectType: .permanent)
        }

        // Version info
        app.get("version") { req in
            return ["version": VersionManager.shared.getCurrentVersion().stringValue, "name": "Cortland Cast Server"]
        }

        // Basic UI page
        app.get("ui") { req -> Response in
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Cortland Cast Server</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 40px; }
                    .status { color: green; font-weight: bold; }
                </style>
            </head>
            <body>
                <h1>Cortland Cast Server</h1>
                <p><span class="status">Status: Running</span></p>
                <p>This is the Swift port of your Music Controller HAOS server.</p>
                <p>Full web interface is available through the Home Assistant integration.</p>
                <h2>API Endpoints</h2>
                <ul>
                    <li><a href="/status">/status</a> - Server status</li>
                    <li><a href="/now_playing">/now_playing</a> - Current track info</li>
                    <li><a href="/settings">/settings</a> - Server settings</li>
                    <li><a href="/artwork/current">/artwork/current</a> - Current track artwork</li>
                    <li>POST /play - Start music</li>
                    <li>POST /pause - Pause music</li>
                    <li>POST /next - Next track</li>
                    <li>POST /previous - Previous track</li>
                    <li>POST /set_volume - Set volume</li>
                    <li>POST /volume_up - Volume up</li>
                    <li>POST /volume_down - Volume down</li>
                </ul>
            </body>
            </html>
            """
            return Response(status: .ok, headers: ["Content-Type": "text/html"], body: .init(string: html))
        }

        // Status endpoint
        app.get("status") { req in
            return ["status": "Cortland Cast Server is running"]
        }

        // Now Playing
        app.get("now_playing") { req in
            return getNowPlaying()
        }

        // Settings
        app.get("settings") { req in
            let settings = SettingsManager.shared.get()
            return MySettings(port: settings.port, open_browser: settings.openBrowser)
        }

        app.put("settings") { req -> MySettings in
            let newSettings = try req.content.decode(MySettings.self)
            var settings = SettingsManager.shared.get()
            settings.port = newSettings.port
            settings.openBrowser = newSettings.open_browser
            SettingsManager.shared.update(settings)
            return newSettings
        }

        // Playback controls - Migrated to ScriptingBridge for preferred performance
        app.post("playpause") { req in
            if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
                music.perform(Selector(("playpause")))
                return ["status": "ok"]
            } else {
                return fallbackAppleScript("tell application \"Music\" to playpause")
            }
        }

        app.post("pause") { req in
            if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
                music.perform(Selector(("pause")))
                return ["status": "paused"]
            } else {
                let result = fallbackAppleScript("tell application \"Music\" to pause")
                return result.mapValues { $0 == "ok" ? "paused" : $0 }
            }
        }

        app.post("next") { req in
            if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
                music.perform(Selector(("nextTrack")))
                return ["status": "ok"]
            } else {
                return fallbackAppleScript("tell application \"Music\" to next track")
            }
        }

        app.post("previous") { req in
            if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
                music.perform(Selector(("previousTrack")))
                return ["status": "ok"]
            } else {
                return fallbackAppleScript("tell application \"Music\" to previous track")
            }
        }

        app.post("quit") { req in
            req.application.shutdown()
            return ["status": "shutting down"]
        }

        // Browse endpoints for Home Assistant media browser
        app.get("playlists") { req -> [String] in
            if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
                if let playlists = music.value(forKey: "userPlaylists") as? [NSObject] {
                    let names = playlists.compactMap { $0.value(forKey: "name") as? String }
                    return names
                } else if let playlists = music.value(forKey: "playlists") as? [NSObject] {
                    let names = playlists.compactMap { $0.value(forKey: "name") as? String }
                    return names
                } else {
                    print("ScriptingBridge: no playlists found")
                }
            } else {
                print("ScriptingBridge: Music app not found")
            }
            return []
        }

        app.get("albums") { req -> [String] in
            let script = """
            tell application "Music"
                set album_names to album of every track of library playlist 1

                set unique_albums to {}
                set seen to ""
                set AppleScript's text item delimiters to "|"

                repeat with a in album_names
                    set theAlbum to contents of a
                    if theAlbum is not "" then
                        if seen does not contain ("|" & theAlbum & "|") then
                            set end of unique_albums to theAlbum
                            set seen to seen & "|" & theAlbum & "|"
                        end if
                    end if
                end repeat

                if length of unique_albums > 500 then
                    set unique_albums to items 1 thru 500 of unique_albums
                end if
                set AppleScript's text item delimiters to linefeed
                return unique_albums as text
            end tell
            """
            let result = runAppleScript(script)
            if result.success {
                let albumString = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if albumString.isEmpty {
                    return []
                }
                let items = albumString.split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                let uniqueAlbums = Array(Set(items)).sorted()
                return uniqueAlbums
            } else {
                print("Albums script failed: \(result.error)")
            }
            return []
        }

        app.get("artists") { req -> [String] in
            let script = """
            tell application "Music"
                set artist_names to artist of every track of library playlist 1
                set unique_artists to {}
                set seen to ""
                set AppleScript's text item delimiters to "|"

                repeat with a in artist_names
                    set theArtist to contents of a
                    if theArtist is not "" then
                        if seen does not contain ("|" & theArtist & "|") then
                            set end of unique_artists to theArtist
                            set seen to seen & "|" & theArtist & "|"
                        end if
                    end if
                end repeat

                if length of unique_artists > 500 then
                    set unique_artists to items 1 thru 500 of unique_artists
                end if
                set AppleScript's text item delimiters to linefeed
                return unique_artists as text
            end tell
            """
            let result = runAppleScript(script)
            if result.success {
                let artistString = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if artistString.isEmpty {
                    return []
                }
                let items = artistString.split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                return items.sorted()
            } else {
                print("Artists script failed: \(result.error)")
            }
            return []
        }

        // Device volumes for Home Assistant
        app.get("device_volumes") { req in
            let script = """
            tell application "Music"
                return sound volume
            end tell
            """
            let result = runAppleScript(script)
            if result.success, let vol = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return ["0": vol]
            } else {
                return ["0": 0]
            }
        }

        app.get("devices") { req in
            return [Device(id: 0, name: "Main Output", volume: getVolume())]
        }

        // Volume control endpoints
        app.post("set_volume") { req -> VolumeResponse in
            let volumeReq = try req.content.decode(VolumeRequest.self)
            let volume = volumeReq.volume
            let clampedVolume = min(100, max(0, volume))
            let script = "tell application \"Music\" to set sound volume to \(clampedVolume)"
            let result = runAppleScript(script)
            return VolumeResponse(success: result.success, volume: clampedVolume)
        }

        app.post("volume_up") { req -> VolumeResponse in
            let currentVolume = getVolume()
            let newVolume = min(100, currentVolume + 10)
            let script = "tell application \"Music\" to set sound volume to \(newVolume)"
            let result = runAppleScript(script)
            return VolumeResponse(success: result.success, volume: newVolume)
        }

        app.post("volume_down") { req -> VolumeResponse in
            let currentVolume = getVolume()
            let newVolume = max(0, currentVolume - 10)
            let script = "tell application \"Music\" to set sound volume to \(newVolume)"
            let result = runAppleScript(script)
            return VolumeResponse(success: result.success, volume: newVolume)
        }

        // Artwork Caching - Main endpoint for Home Assistant integration
        app.get("artwork") { req -> Response in
            let token = req.query[String.self, at: "tok"] ?? ""
            let refresh = req.query[Bool.self, at: "refresh"] ?? false
            // Use centralized Library directory as requested
            let cacheDir = self.getArtworkCacheDirectory()
            let cacheFile = cacheDir.appendingPathComponent("\(token).jpg")

            // Create cache directory if needed
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            // Check if cached artwork exists and we're not forcing refresh
            if !refresh, FileManager.default.fileExists(atPath: cacheFile.path) {
                do {
                    let data = try Data(contentsOf: cacheFile)
                    return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: data))
                } catch {
                    // Fall through to fetch fresh artwork
                }
            }

            // Fetch fresh artwork from Music.app - save directly to temp file
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let tempFile = tempDir.appendingPathComponent("music_artwork_temp_\(UUID().uuidString).jpg")
            let tempFilePath = tempFile.path

            let script = """
            tell application "Music"
                try
                    set t to current track
                    if t is missing value then return "NOART"
                    if (count of artworks of t) = 0 then return "NOART"
                    set tempPath to "\(tempFilePath)"
                    set fileRef to open for access POSIX file tempPath with write permission
                    set eof of fileRef to 0
                    set rawData to data of artwork 1 of t
                    write rawData to fileRef
                    close access fileRef
                    return tempPath
                on error
                    return "NOART"
                end try
            end tell
            """

            let result = runAppleScript(script)
            if !result.success || result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "NOART" {
                // Return a blank PNG as placeholder
                let blankPNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 0x00, 0x00, 0x0B, 0x13, 0x00, 0x00, 0x0B, 0x13, 0x01, 0x00, 0x9A, 0x9C, 0x18, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x18, 0x57, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
                return Response(status: .ok, headers: ["Content-Type": "image/png"], body: .init(data: Data(blankPNG)))
            }

            // Read the artwork from the temp file and copy to cache
            do {
                let artworkData = try Data(contentsOf: tempFile)
                try artworkData.write(to: cacheFile)

                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFile.path)

                return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: artworkData))
            } catch {

                return Response(status: .internalServerError, body: "Failed to read cached artwork")
            }
        }

       app.get("album_artwork") { req -> Response in
            let albumName = req.query[String.self, at: "name"]?.removingPercentEncoding ?? ""
            if albumName.isEmpty {
                return Response(status: .badRequest, body: "Album name required")
            }

            let refresh = req.query[Bool.self, at: "refresh"] ?? false
            let cacheDir = self.getArtworkCacheDirectory()

            // Create album-specific cache key
            let albumToken = albumName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
            let cacheFile = cacheDir.appendingPathComponent("\(albumToken).jpg")

            // Create cache directory if needed
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            // Check if cached artwork exists and we're not forcing refresh
            if !refresh, FileManager.default.fileExists(atPath: cacheFile.path) {
                do {
                    let data = try Data(contentsOf: cacheFile)
                    return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: data))
                } catch {
                    // Fall through to fetch fresh artwork
                }
            }

            // Fetch artwork from Music.app by finding first track of the album - save directly to temp file
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let tempFile = tempDir.appendingPathComponent("album_artwork_temp_\(UUID().uuidString).jpg")

            // Properly escape the album name for AppleScript string literal
            let appleScriptEscapedName = albumName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let script = """
            tell application "Music"
                try
                    -- Find first track from this album
                    set foundTracks to every track of library playlist 1 whose album is "\(appleScriptEscapedName)"
                    if (count of foundTracks) = 0 then return "NOALBUM"

                    set albumTrack to item 1 of foundTracks
                    if albumTrack is missing value then return "NOART"

                    -- Check if this track has artwork
                    if (count of artworks of albumTrack) = 0 then return "NOART"

                    set tempPath to "\(tempFile.path)"
                    set fileRef to open for access tempPath with write permission
                    set eof fileRef to 0
                    set rawData to data of artwork 1 of albumTrack
                    write rawData to fileRef
                    close access fileRef
                    return tempPath
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """

            let result = runAppleScript(script)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

            if !result.success || output == "NOART" || output == "NOALBUM" || output.hasPrefix("ERROR:") {
                // Return a blank PNG as placeholder
                let blankPNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 0x00, 0x00, 0x0B, 0x13, 0x00, 0x00, 0x0B, 0x13, 0x01, 0x00, 0x9A, 0x9C, 0x18, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x18, 0x57, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
                return Response(status: .ok, headers: ["Content-Type": "image/png"], body: .init(data: Data(blankPNG)))
            }

            // Read the artwork from the temp file and copy to cache
            do {
                let artworkData = try Data(contentsOf: tempFile)
                try artworkData.write(to: cacheFile)

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempFile)

                return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: artworkData))
            } catch {
                // Clean up temp file on error
                try? FileManager.default.removeItem(at: tempFile)
                return Response(status: .internalServerError, body: "Failed to read cached artwork")
            }
        }

        // Secondary artwork endpoints
        app.get("artwork", "current") { req -> Response in
            return await self.getCurrentArtwork(req: req)
        }

        app.get("artwork", "album", ":album", ":artist") { req -> Response in
            let album = req.parameters.get("album")?.removingPercentEncoding ?? ""
            let artist = req.parameters.get("artist")?.removingPercentEncoding ?? ""
            return await self.getAlbumArtwork(req: req, album: album, artist: artist)
        }

        // WebSocket endpoint for real-time updates
        app.webSocket("ws") { req, ws in
            ws.onText { ws, text in
                print("WS message: \(text)")
            }

            let initialEvent = """
            event: connection
            data: {"type": "ping", "message": "WS connected"}
            """
            ws.send(initialEvent)

            // Keep connection alive and monitor state changes
            monitorMusicState { change in
                let eventData = "data: {\"type\": \"\(change.type)\", \"data\": \(change.json)}\n"
                print("WS sending \(change.type) event: \(String(eventData.prefix(100)))...")
                ws.send(eventData)
            }
        }

        app.post("resume") { req in
            let script = "tell application \"Music\" to play"
            let result = runAppleScript(script)
            return ["status": result.success ? "ok" : "error"]
        }

        app.get("shuffle") { req -> [String: Bool] in
            if let enabled = getShuffleEnabled() {
                return ["enabled": enabled]
            } else {
                let result = runAppleScript("""
                tell application "Music"
                    try
                        return (shuffle enabled) as text
                    on error
                        return "false"
                    end try
                end tell
                """)
                if result.success, let boolValue = Bool(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return ["enabled": boolValue]
                }
            }
            return ["enabled": false]
        }

        app.post("shuffle") { req -> [String: Bool] in
            let shuffleReq = try req.content.decode(ShuffleRequest.self)
            let flag = shuffleReq.enabled ? "true" : "false"
            let script = """
            tell application "Music"
                set shuffle enabled to \(flag)
            end tell
            """
            let result = runAppleScript(script)
            return ["ok": result.success, "enabled": shuffleReq.enabled]
        }

        app.get("repeat") { req -> [String: String] in
            let result = runAppleScript("""
            tell application "Music"
                try
                    return (song repeat) as text
                on error
                    return "off"
                end try
            end tell
            """)
            let mode = result.success ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : "off"
            return ["mode": mode]
        }

        app.post("repeat") { req -> [String: Bool] in
            let repeatReq = try req.content.decode(RepeatRequest.self)
            let mode = repeatReq.mode
            let validModes = ["off", "one", "all"]
            let safeMode = validModes.contains(mode) ? mode : "off"
            let script = """
            tell application "Music"
                set song repeat to \(safeMode)
            end tell
            """
            let result = runAppleScript(script)
            return ["ok": result.success, "mode": safeMode == mode]
        }

        // Music Browse Track Retrieval
        app.get("playlist_tracks") { req -> PlaylistTracksResponse in
            let name = req.query[String.self, at: "name"] ?? ""
            let limit = req.query[Int.self, at: "limit"] ?? 500 // Default limit of 500 tracks
            if name.isEmpty { return PlaylistTracksResponse(tracks: [], truncated: false, total: 0, limit: limit, message: nil, error: nil) }

            // Special handling for known large playlists
            let knownLargePlaylists = ["Music", "Library"]
            let isLargePlaylist = knownLargePlaylists.contains { name.lowercased().contains($0.lowercased()) }

            if isLargePlaylist {
                // For large playlists, return a warning instead of trying to enumerate
                return PlaylistTracksResponse(tracks: ["This playlist is too large to display all tracks"],
                                            truncated: true,
                                            total: -1,
                                            limit: limit,
                                            message: "Playlist '\(name)' contains too many tracks to list. Use the play endpoint to start playback directly.",
                                            error: nil)
            }

            let script = """
            tell application "Music"
                try
                    set thePlaylist to first playlist whose name is \"\(name)\"
                    set playlistTrackCount to count of tracks of thePlaylist

                    -- Check if playlist is suspiciously large
                    if playlistTrackCount > 500 then
                        return "TOO_LARGE:" & playlistTrackCount
                    end if

                    set trackList to {}
                    set maxTracks to \(limit)
                    set trackCount to 0

                    repeat with tr in tracks of thePlaylist
                        if trackCount >= maxTracks then exit repeat
                        set trackName to name of tr as string
                        if trackName is not "" then
                            set end of trackList to trackName
                            set trackCount to trackCount + 1
                        end if
                    end repeat

                    set resultText to "COUNT:" & (count of tracks of thePlaylist) & "\\n"
                    set AppleScript's text item delimiters to linefeed
                    set resultText to resultText & trackList as text
                    return resultText
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """

            let result = runAppleScript(script)
            if result.success {
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

                if output.hasPrefix("TOO_LARGE:") {
                    let totalCount = output.replacingOccurrences(of: "TOO_LARGE:", with: "")
                    return PlaylistTracksResponse(tracks: ["This playlist contains \(totalCount) tracks and is too large to display"],
                                                truncated: true,
                                                total: Int(totalCount) ?? 0,
                                                limit: limit,
                                                message: "Playlist too large to enumerate. Use play endpoint for playback.",
                                                error: nil)
                } else if output.hasPrefix("ERROR:") {
                    return PlaylistTracksResponse(tracks: [], truncated: false, total: 0, limit: limit, message: nil, error: output.replacingOccurrences(of: "ERROR:", with: ""))
                }

                let lines = output.split(separator: "\n").map { String($0) }
                var totalTracks = 0
                var tracks: [String] = []

                for line in lines {
                    if line.hasPrefix("COUNT:") {
                        totalTracks = Int(line.replacingOccurrences(of: "COUNT:", with: "")) ?? 0
                    } else if !line.isEmpty {
                        tracks.append(line.trimmingCharacters(in: .whitespaces))
                    }
                }

                return PlaylistTracksResponse(tracks: tracks.sorted(),
                                            truncated: tracks.count < totalTracks,
                                            total: totalTracks,
                                            limit: limit,
                                            message: nil,
                                            error: nil)
            } else {
                return PlaylistTracksResponse(tracks: [], truncated: false, total: 0, limit: limit, message: nil, error: "AppleScript execution failed")
            }
        }

        app.get("album_tracks") { req -> [String] in
            let name = req.query[String.self, at: "name"] ?? ""
            if name.isEmpty { return [] }
            // Properly escape the album name for AppleScript string literal
            let appleScriptEscapedName = name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
                try
                    set track_list to every track of library playlist 1 whose album is \"\(appleScriptEscapedName)\"
                on error
                    set track_list to {}
                end try
                set song_names to {}
                repeat with t in track_list
                    try
                        set n to name of t
                        if n is not missing value and n is not "" then set end of song_names to n
                    end try
                end repeat
                set AppleScript's text item delimiters to linefeed
                return song_names as text
            end tell
            """
            let result = runAppleScript(script)
            if result.success {
                let trackString = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if trackString.isEmpty {
                    return []
                }
                let items = trackString.split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                return items.sorted()
            } else {
                return []
            }
        }

        app.get("artist_albums") { req -> [String] in
            let name = req.query[String.self, at: "name"] ?? ""
            if name.isEmpty { return [] }
            let script = """
            tell application "Music"
                try
                    set album_list to album of every track of library playlist 1 whose artist is \"\(name)\"
                on error
                    set album_list to {}
                end try
                set unique_albums to {}
                set seen to ""
                repeat with alb in album_list
                    try
                        set albName to alb as string
                        if albName is not "" and seen does not contain ("|" & albName & "|") then
                            set end of unique_albums to albName
                            set seen to seen & "|" & albName & "|"
                        end if
                    end try
                end repeat
                set AppleScript's text item delimiters to linefeed
                return unique_albums as text
            end tell
            """
            let result = runAppleScript(script)
            if result.success {
                let albumString = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if albumString.isEmpty {
                    return []
                }
                let items = albumString.split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                return items.sorted()
            } else {
                return []
            }
        }

        // Additional endpoints in routes method
        app.post("seek") { req -> [String: Bool] in
            let seekReq = try req.content.decode(SeekRequest.self)
            let script = "tell application \"Music\" to set player position to \(seekReq.position)"
            let result = runAppleScript(script)
            return ["ok": result.success]
        }

        // Updated play endpoint to handle specific media types
        app.post("play") { req in
            let playReq = try req.content.decode(PlayRequest.self)
            print("Play request: type=\(playReq.type ?? "nil"), name=\(playReq.name ?? "nil"), album=\(playReq.album ?? "nil")")
            if let mediaType = playReq.type, let mediaName = playReq.name {
                // Properly escape media names for AppleScript string literals
                let appleScriptEscapedName = mediaName
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

                switch mediaType {
                case "playlist":
                    let script = """
                    tell application "Music"
                        try
                            set thePlaylist to first playlist whose name is \"\(appleScriptEscapedName)\"
                            play thePlaylist
                            return "PLAYLIST_OK"
                        on error errMsg
                            return "PLAYLIST_ERROR: " & errMsg
                        end try
                    end tell
                    """
                    let result = runAppleScript(script)
                    print("Playlist play result: success=\(result.success), output='\(result.output)'")
                    return ["status": result.success && result.output == "PLAYLIST_OK" ? "playing" : "error"]
                case "album":
                    // Create a temporary playlist with all album tracks and play it
                    let script = """
                    tell application "Music"
                        try
                            set albumName to \"\(appleScriptEscapedName)\"

                            -- Grab all tracks for this album from the main library
                            set albumTracks to every track of library playlist 1 whose album is albumName

                            if (count of albumTracks) is 0 then
                                return "ALBUM_NOT_FOUND"
                            end if

                            -- Name of a temporary playlist we control
                            set tempPlaylistName to "Music Controller"

                            -- Get or create the temp playlist
                            if not (exists user playlist tempPlaylistName) then
                                make new user playlist with properties {name:tempPlaylistName}
                            end if
                            set tempPlaylist to user playlist tempPlaylistName

                            -- Clear it out
                            delete every track of tempPlaylist

                            -- Add the album tracks to the temp playlist
                            repeat with t in albumTracks
                                duplicate t to tempPlaylist
                            end repeat

                            -- Start playing from the first track in that playlist
                            play tempPlaylist

                            return "ALBUM_OK"

                        on error errMsg
                            return "ALBUM_ERROR: " & errMsg
                        end try
                    end tell
                    """
                    let result = runAppleScript(script)
                    print("Album play result: success=\(result.success), output='\(result.output)'")
                    return ["status": result.success && result.output == "ALBUM_OK" ? "playing" : "error"]
                case "track":
                    // Play specific track from the specified album
                    if let albumName = playReq.album {
                        // Properly escape album name for AppleScript
                        let appleScriptEscapedAlbum = albumName
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                        let script = """
                        tell application "Music"
                            try
                                set foundTrack to first track of library playlist 1 whose album is \"\(appleScriptEscapedAlbum)\" and name is \"\(appleScriptEscapedName)\"
                                play foundTrack
                                return "TRACK_OK"
                            on error errMsg
                                return "TRACK_ERROR: " & errMsg
                            end try
                        end tell
                        """
                        let result = runAppleScript(script)
                        print("Track play result: success=\(result.success), output='\(result.output)'")
                        return ["status": result.success && result.output == "TRACK_OK" ? "playing" : "error"]
                    } else {
                        return ["status": "error", "message": "album parameter required for track playback"]
                    }
                case "artist":
                    // Play all tracks from all albums by the artist (supports shuffle)
                    let shuffleEnabled = playReq.shuffle ?? false
                    let shuffleFlag = shuffleEnabled ? "true" : "false"
                    let script = """
                    tell application "Music"
                        try
                            set artistName to \"\(appleScriptEscapedName)\"
                            set artistTracks to every track of library playlist 1 whose artist is artistName

                            if (count of artistTracks) is 0 then
                                return "ARTIST_NOT_FOUND"
                            end if

                            -- Create temporary playlist for artist playback
                            set tempPlaylistName to "Music Controller - Artist"

                            -- Get or create the temp playlist
                            if not (exists user playlist tempPlaylistName) then
                                make new user playlist with properties {name:tempPlaylistName}
                            end if
                            set tempPlaylist to user playlist tempPlaylistName

                            -- Clear it out
                            delete every track of tempPlaylist

                            -- Add all artist tracks to the temp playlist
                            repeat with t in artistTracks
                                duplicate t to tempPlaylist
                            end repeat

                            -- Set shuffle mode if requested
                            set shuffle enabled to \(shuffleFlag)

                            -- Start playing from the first track in that playlist
                            play tempPlaylist

                            return "ARTIST_OK"

                        on error errMsg
                            return "ARTIST_ERROR: " & errMsg
                        end try
                    end tell
                    """
                    let result = runAppleScript(script)
                    print("Artist play result: success=\(result.success), output='\(result.output)', shuffle=\(shuffleEnabled)")
                    return ["status": result.success && result.output == "ARTIST_OK" ? "playing" : "error"]
                default:
                    // Fall back to start
                    let result = runAppleScript("tell application \"Music\" to play")
                    return ["status": result.success ? "playing" : "error"]
                }
            } else {
                // Original behavior - just start playing
                let result = runAppleScript("tell application \"Music\" to play")
                print("Fallback play result: success=\(result.success)")
                return ["status": result.success ? "playing" : "error"]
            }
        }

        // AirPlay Device Management Endpoints
        app.get("airplay", "devices") { req -> [AirPlayDevice] in
            let script = """
            tell application "Music"
                try
                    set airplayDevices to {}

                    -- Get current AirPlay devices
                    set deviceList to (AirPlay devices)

                    repeat with d in deviceList
                        try
                            set deviceName to name of d
                            set deviceID to (persistent ID of d) as text
                            set deviceActive to selected of d
                            set deviceVolume to sound volume of d
                            set deviceKind to kind of d

                            -- Check if device is disconnected (name starts with "-" or is marked unavailable)
                            set deviceAvailable to true
                            if deviceName starts with "-" or deviceName is "" or deviceName is missing value then
                                set deviceAvailable to false
                                -- Try to get a more user-friendly name if available
                                if deviceName starts with "-" and (count of deviceName) > 1 then
                                    set deviceName to text from character 2 to -1 of deviceName
                                else if deviceName is "" or deviceName is missing value then
                                    set deviceName to "Unknown Device"
                                end if
                            end if

                            -- Skip CarPlay devices
                            if deviceKind is not "CarPlay" then
                                set deviceInfo to "ID:" & deviceID & "|NAME:" & deviceName & "|ACTIVE:" & (deviceActive as text) & "|VOLUME:" & (deviceVolume as text) & "|KIND:" & deviceKind & "|AVAILABLE:" & (deviceAvailable as text)
                                set end of airplayDevices to deviceInfo
                            end if
                        on error deviceError
                            -- Skip devices that throw errors (often network unavailable devices)
                            log "Skipping problematic device: " & deviceError
                        end try
                    end repeat

                    set AppleScript's text item delimiters to linefeed
                    return airplayDevices as text
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """

            let result = runAppleScript(script)
            print("AirPlay devices result: success=\(result.success), output='\(result.output)'")

            if !result.success || result.output.hasPrefix("ERROR:") {
                return []
            }

            let deviceStrings = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .map { String($0) }

            var devices: [AirPlayDevice] = []
            for deviceStr in deviceStrings {
                // Parse format: ID:xxx|NAME:xxx|ACTIVE:true|VOLUME:50|KIND:xxx|AVAILABLE:false
                var deviceID = ""
                var deviceName = ""
                var deviceActive = false
                var deviceVolume = 0
                var deviceKind = ""
                var deviceAvailable = true

                let parts = deviceStr.split(separator: "|")

                for part in parts {
                    let keyValue = part.split(separator: ":", maxSplits: 1)
                    if keyValue.count == 2 {
                        let key = String(keyValue[0]).lowercased()
                        let value = String(keyValue[1])

                        switch key {
                        case "id":
                            deviceID = value
                        case "name":
                            deviceName = value
                        case "active":
                            deviceActive = (value.lowercased() == "true")
                        case "volume":
                            deviceVolume = Int(value) ?? 0
                        case "kind":
                            deviceKind = value
                        case "available":
                            deviceAvailable = (value.lowercased() == "true")
                        default:
                            break
                        }
                    }
                }

                if !deviceID.isEmpty && !deviceName.isEmpty {
                    let device = AirPlayDevice(
                        id: deviceID,
                        name: deviceName,
                        active: deviceActive,
                        volume: deviceVolume,
                        kind: deviceKind,
                        available: deviceAvailable
                    )
                    devices.append(device)
                }
            }

            print("Parsed AirPlay devices: \(devices.count) devices")
            return devices
        }

        struct AirPlaySetActiveRequest: Content {
            let device_ids: [String]
        }

        app.post("airplay", "set_active") { req -> [String: Bool] in
            let activeReq = try req.content.decode(AirPlaySetActiveRequest.self)
            print("Setting active devices: \(activeReq.device_ids)")

            // If no devices specified, deactivate all
            if activeReq.device_ids.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set allDevices to (AirPlay devices)
                        repeat with d in allDevices
                            try
                                set selected of d to false
                            end try
                        end repeat
                        return "OK"
                    on error errMsg
                        return "ERROR:" & errMsg
                    end try
                end tell
                """
                let result = runAppleScript(script)
                print("Deactivate all result: \(result.output)")
                return ["ok": result.success && result.output.contains("OK")]
            }

            // Activate specific devices by matching persistent ID
            let deviceIDsStr = activeReq.device_ids.map { "\"\($0)\"" }.joined(separator: ", ")

            let script = """
            tell application "Music"
                try
                    set targetIDs to {\(deviceIDsStr)}
                    set allDevices to (AirPlay devices)

                    repeat with d in allDevices
                        try
                            set devID to (persistent ID of d) as text
                            if targetIDs contains devID then
                                if not (selected of d) then
                                    set selected of d to true
                                end if
                            else
                                if (selected of d) then
                                    set selected of d to false
                                end if
                            end if
                        on error devError
                            log "Device error: " & devError
                        end try
                    end repeat

                    return "OK"
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """

            let result = runAppleScript(script)
            print("Set AirPlay active result: success=\(result.success), output='\(result.output)'")
            return ["ok": result.success && result.output.contains("OK")]
        }

        struct AirPlayVolumeRequest: Content {
            let device_id: String
            let volume: Int
        }

        app.post("airplay", "set_volume") { req -> [String: Bool] in
            let volumeReq = try req.content.decode(AirPlayVolumeRequest.self)
            let deviceID = volumeReq.device_id
            let volume = min(max(volumeReq.volume, 0), 100)

            let script = """
            tell application "Music"
                try
                    set allDevices to (AirPlay devices)

                    repeat with d in allDevices
                        set devID to (persistent ID of d) as text
                        if devID is "\(deviceID)" then
                            set sound volume of d to \(volume)
                            return "OK"
                        end if
                    end repeat

                    return "NOTFOUND"
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """

            let result = runAppleScript(script)
            print("Set AirPlay volume result: success=\(result.success), output='\(result.output)'")
            return ["ok": result.success && result.output.contains("OK")]
        }
    }

    private func getArtworkCacheDirectory() -> URL {
        let configDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/CortlandCastServer")
        let artworkDirectory = configDirectory.appendingPathComponent("artwork")

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
            print("Artwork cache directory created at: \(artworkDirectory.path)")
        } catch {
            print("Failed to create artwork cache directory: \(error)")
        }

        return artworkDirectory
    }

    private func getArtworkCachePath(for identifier: String, size: Int = 300) -> URL {
        let cacheDir = getArtworkCacheDirectory()
        let filename = "\(identifier)_\(size).jpg"
        return cacheDir.appendingPathComponent(filename)
    }

    private func cacheArtwork(imageData: Data, identifier: String, size: Int = 300) {
        let cachePath = getArtworkCachePath(for: identifier, size: size)
        try? imageData.write(to: cachePath, options: .atomic)
    }

    private func getCachedArtwork(identifier: String, size: Int = 300) -> Data? {
        let cachePath = getArtworkCachePath(for: identifier, size: size)
        return try? Data(contentsOf: cachePath)
    }

    private func getCurrentArtwork(req: Request) async -> Response {
        let size = req.query[Int.self, at: "size"] ?? 300
        print("🎨 Getting current artwork for size: \(size)")

        // Check cached current track artwork first
        if let cachedData = getCachedArtwork(identifier: "current_track", size: size) {
            print("✅ Returning cached current track artwork, size: \(cachedData.count) bytes")
            return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: cachedData))
        }

        print("📁 No cached artwork found, fetching from Music.app...")

        // Use temp file approach to get artwork data (mirroring original App.swift implementation)
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempFile = tempDir.appendingPathComponent("music_current_artwork_\(UUID().uuidString).jpg")
        let tempPath = tempFile.path
        print("📝 Temp file path: \(tempPath)")

        let script = """
        tell application "Music"
            try
                set theTrack to current track
                if theTrack is missing value then return "NOART"
                if (count of artworks of theTrack) is 0 then return "NOART"
                set theArtwork to artwork 1 of theTrack
                set fileRef = open for access POSIX file "\(tempPath)" with write permission
                set eof fileRef to 0
                write (data of theArtwork) to fileRef
                close access fileRef
                return "\(tempPath)"
            on error errMsg
                return "NOART:" & errMsg
            end try
        end tell
        """

        let result = runAppleScript(script)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔄 AppleScript result: success=\(result.success), output='\(output)'")

        // Clean up temp file on failure
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        if result.success && !output.hasPrefix("NOART") && output.contains("music_current_artwork_") {
            print("📖 Reading artwork from temp file: \(output)")
            // Try to read the saved artwork file
            if let artworkData = try? Data(contentsOf: URL(fileURLWithPath: tempPath)), !artworkData.isEmpty {
                print("📄 Loaded artwork data: \(artworkData.count) bytes")

                // Cache and return the artwork
                cacheArtwork(imageData: artworkData, identifier: "current_track", size: size)
                print("💾 Cached current track artwork")

                return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: artworkData))
            } else {
                print("❌ Failed to read artwork data from temp file")
            }
        } else {
            print("❌ No artwork returned - result=\(result.success), output prefix=\(output.hasPrefix("NOART"))")
        }

        return Response(status: .notFound)
    }

    private func getAlbumArtwork(req: Request, album: String, artist: String) async -> Response {
        let size = req.query[Int.self, at: "size"] ?? 300
        let cacheKey = "\(album)_\(artist)".replacingOccurrences(of: "/", with: "_")

        // Check cache first
        if let cachedData = getCachedArtwork(identifier: cacheKey, size: size) {
            return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: cachedData))
        }

        // Search for track with matching album/artist and get artwork - use temp file
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempFile = tempDir.appendingPathComponent("album_artwork_\(UUID().uuidString).jpg")
        let tempPath = tempFile.path
        let script = """
        tell application "Music"
            try
                -- Find tracks with matching artist and album
                set foundTracks to every track of playlist 1 whose artist is "\(artist)" and album is "\(album)"
                if foundTracks is not {} then
                    set theTrack = item 1 of foundTracks
                    if artworks of theTrack is not {} then
                        set theArtwork = artwork 1 of theTrack
                        set fileRef = open for access POSIX file "\(tempPath)" with write permission
                        set eof fileRef to 0
                        write (data of theArtwork) to fileRef
                        close access fileRef
                        return "\(tempPath)"
                    end if
                end if
                return "NOART"
            on error
                return "NOART"
            end try
        end tell
        """

        let result = runAppleScript(script)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up temp file
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        if result.success && !output.hasPrefix("NOART") && output.contains("album_artwork_") {
            // Try to read the saved artwork file
            if let artworkData = try? Data(contentsOf: URL(fileURLWithPath: tempPath)), !artworkData.isEmpty {
                // Cache the artwork
                cacheArtwork(imageData: artworkData, identifier: cacheKey, size: size)
                return Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: .init(data: artworkData))
            }
        }

        return Response(status: .notFound)
    }
}



func getVolume() -> Int {
    let script = "tell application \"Music\" to return sound volume"
    let result = runAppleScript(script)
    return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

func getShuffleEnabled() -> Bool? {
    if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
        return (music.value(forKey: "shuffleEnabled") as? NSNumber)?.boolValue
    }
    return nil
}

func fallbackAppleScript(_ script: String) -> [String: String] {
    let result = runAppleScript(script)
    return ["status": result.success ? "ok" : "error"]
}

func getNowPlaying() -> [String: Any] {
    var nowPlaying: [String: Any] = [
        "state": "unknown",
        "title": "",
        "artist": "",
        "album": "",
        "duration": 0.0,
        "position": 0.0,
        "volume": 0,
        "shuffle": false,
        "repeat": "off"
    ]

    if let music = SBApplication(bundleIdentifier: "com.apple.Music") {
        // Get current track info
        if let currentTrack = music.value(forKey: "currentTrack") as? NSObject {
            nowPlaying["title"] = currentTrack.value(forKey: "name") as? String ?? ""
            nowPlaying["artist"] = currentTrack.value(forKey: "artist") as? String ?? ""
            nowPlaying["album"] = currentTrack.value(forKey: "album") as? String ?? ""
            nowPlaying["duration"] = currentTrack.value(forKey: "duration") as? Double ?? 0.0

            // Generate artwork token using album name only to avoid duplicates (same as album_artwork endpoint)
            let trackAlbum = nowPlaying["album"] as? String ?? "no_album"
            let sanitizedAlbum = trackAlbum.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
            let artworkToken = sanitizedAlbum.isEmpty ? "no_album" : sanitizedAlbum
            nowPlaying["artwork_token"] = artworkToken
        }

        // Get player state
        let isPlaying = music.value(forKey: "playerState") as? NSNumber
        nowPlaying["is_playing"] = isPlaying?.intValue == 1 ? true : false

        let scriptResult = runAppleScript("tell application \"Music\" to player state as text")
        if scriptResult.success {
            let state = scriptResult.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            nowPlaying["state"] = state
        }

        // Get additional info
        nowPlaying["position"] = music.value(forKey: "playerPosition") as? Double ?? 0.0
        nowPlaying["volume"] = music.value(forKey: "soundVolume") as? Int ?? 0

        // Get shuffle and repeat
        nowPlaying["shuffle"] = getShuffleEnabled() ?? false

        let repeatResult = runAppleScript("tell application \"Music\" to return song repeat as text")
        if repeatResult.success {
            nowPlaying["repeat"] = repeatResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let altRepeatResult = runAppleScript("tell application \"Music\" to return (song repeat) as text")
            if altRepeatResult.success {
                nowPlaying["repeat"] = altRepeatResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    return nowPlaying
}

func monitorMusicState(changeHandler: @escaping (StateChange) -> Void) {
    Task {
        while true {
            await checkForStateChanges(changeHandler: changeHandler)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

func getFullState() async -> String {
    // Return current complete state as JSON string for WebSocket clients
    let state = await getCurrentFullState()
    // Convert to JSON string
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: state)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        print("Full state JSON: \(jsonString.prefix(200))...")
        return jsonString
    } catch {
        return "{}"
    }
}

func getCurrentFullState() async -> [String: Any] {
    // Get complete current state snapshot
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return ["error": "Music app not available"]
    }

    var state: [String: Any] = [
        "player_state": "unknown",
        "shuffle_enabled": false,
        "repeat_mode": "off",
        "volume": 0,
        "current_track": [
            "title": "",
            "artist": "",
            "album": "",
            "duration": 0.0
        ] as [String: Any],
        "position": 0.0
    ]

    // Get player state
    let scriptResult = runAppleScript("tell application \"Music\" to player state as text")
    let currentState = scriptResult.success ? scriptResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : "unknown"
    state["player_state"] = currentState

    // Get shuffle/repeat settings
    if let shuffleNS = music.value(forKey: "shuffleEnabled") as? NSNumber {
        state["shuffle_enabled"] = shuffleNS.boolValue
    }

    let repeatResult = runAppleScript("tell application \"Music\" to song repeat as text")
    if repeatResult.success {
        state["repeat_mode"] = repeatResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Get volume
    if let volume = music.value(forKey: "soundVolume") as? NSNumber {
        state["volume"] = volume.intValue
    }

    // Get position
    let positionResult = runAppleScript("tell application \"Music\" to player position")
    if positionResult.success,
       let position = Double(positionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        state["position"] = position
    }

    // Get current track
    if let currentTrack = music.value(forKey: "currentTrack") as? NSObject {
        var trackState: [String: Any] = [:]
        trackState["title"] = currentTrack.value(forKey: "name") as? String ?? ""
        trackState["artist"] = currentTrack.value(forKey: "artist") as? String ?? ""
        trackState["album"] = currentTrack.value(forKey: "album") as? String ?? ""
        trackState["duration"] = currentTrack.value(forKey: "duration") as? Double ?? 0.0
        state["current_track"] = trackState
    }

    return state
}

func checkForStateChanges(changeHandler: ((StateChange) -> Void)? = nil) async {
    // Comprehensive implementation with position updates, shuffle/repeat monitoring, and AirPlay device changes
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return
    }

    // Use AppleScript for consistent state detection (more reliable than ScriptingBridge for state)
    let scriptResult = runAppleScript("tell application \"Music\" to player state as text")
    let currentState = scriptResult.success ? scriptResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : "unknown"

    // Check volume changes
    if let volume = music.value(forKey: "soundVolume") as? NSNumber {
        if await stateTracker.hasChanged("volume", newValue: volume) {
            let change = StateChange(type: "volume",
                                   data: ["volume": volume.intValue])
            changeHandler?(change)
        }
    }

    // Send position updates using AppleScript for accuracy (always send for debugging)
    let positionScript = "tell application \"Music\" to player position"
    let positionResult = runAppleScript(positionScript)
    if positionResult.success,
       let position = Double(positionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        // Debug log position updates
        print("Position check: state='\(currentState)', position=\(position)")
        if await stateTracker.hasChanged("position_update", newValue: position) {
            let change = StateChange(type: "position",
                                   data: ["position": position])
            changeHandler?(change)
        }
    }

    // Check for track changes (simplified)
    let currentTrack = music.value(forKey: "currentTrack") as? NSObject
    let currentTitle = currentTrack?.value(forKey: "name") as? String ?? ""
    let currentArtist = currentTrack?.value(forKey: "artist") as? String ?? ""

    let trackKey = "\(currentTitle)|\(currentArtist)"
    if await stateTracker.hasChanged("currentTrack", newValue: trackKey),
       !trackKey.isEmpty || trackKey != "|" {

        let change = StateChange(type: "now_playing",
                               data: [
                                "state": currentState,
                                "title": currentTitle,
                                "artist": currentArtist,
                                "album": currentTrack?.value(forKey: "album") as? String ?? "",
                                "position": (music.value(forKey: "playerPosition") as? NSNumber)?.doubleValue ?? 0.0,
                                "duration": (currentTrack?.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0.0,
                                "volume": (music.value(forKey: "soundVolume") as? NSNumber)?.intValue ?? 0,
                                "is_playing": currentState.lowercased().contains("play")
                               ])
        changeHandler?(change)
    }

    // Check shuffle settings using ScriptingBridge
    if let shuffleNS = music.value(forKey: "shuffleEnabled") as? NSNumber,
       await stateTracker.hasChanged("shuffle", newValue: shuffleNS.boolValue) {
        let change = StateChange(type: "shuffle", data: ["enabled": shuffleNS.boolValue])
        changeHandler?(change)
    }

    let repeatScript = "tell application \"Music\" to song repeat as text"
    let repeatResult = runAppleScript(repeatScript)
    let repeatMode = repeatResult.success ? repeatResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : "off"
    if await stateTracker.hasChanged("repeat", newValue: repeatMode) {
        let change = StateChange(type: "repeat",
                               data: ["mode": repeatMode])
        changeHandler?(change)
    }

    // Check AirPlay device changes
    let deviceScript = """
    tell application "Music"
        try
            set airplayDevices to {}

            -- Get current AirPlay devices
            set deviceList to (AirPlay devices)

            repeat with d in deviceList
                try
                    set deviceName to name of d
                    set deviceID to (persistent ID of d) as text
                    set deviceActive to selected of d
                    set deviceVolume to sound volume of d
                    set deviceKind to kind of d

                    -- Skip CarPlay devices
                    if deviceKind is not "CarPlay" then
                        set deviceInfo to "ID:" & deviceID & "|NAME:" & deviceName & "|ACTIVE:" & (deviceActive as text) & "|VOLUME:" & (deviceVolume as text) & "|KIND:" & deviceKind & "|AVAILABLE:" & (deviceActive as text)
                        set end of airplayDevices to deviceInfo
                    end if
                on error deviceError
                    -- Skip devices that throw errors (often network unavailable devices)
                    log "Skipping problematic device: " & deviceError
                end try
            end repeat

            set AppleScript's text item delimiters to linefeed
            return airplayDevices as text
        on error errMsg
            return "ERROR:" & errMsg
        end try
    end tell
    """

    let deviceResult = runAppleScript(deviceScript)
    if deviceResult.success && !deviceResult.output.hasPrefix("ERROR:") {
        let deviceStrings = deviceResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map { String($0) }

        var devices: [[String: Any]] = []
        for deviceStr in deviceStrings {
            // Parse format: ID:xxx|NAME:xxx|ACTIVE:true|VOLUME:50|KIND:xxx|AVAILABLE:true
            var deviceID = ""
            var deviceName = ""
            var deviceActive = false
            var deviceVolume = 0
            var deviceKind = ""
            var deviceAvailable = true

            let parts = deviceStr.split(separator: "|")

            for part in parts {
                let keyValue = part.split(separator: ":", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0]).lowercased()
                    let value = String(keyValue[1])

                    switch key {
                    case "id":
                        deviceID = value
                    case "name":
                        deviceName = value
                    case "active":
                        deviceActive = (value.lowercased() == "true")
                    case "volume":
                        deviceVolume = Int(value) ?? 0
                    case "kind":
                        deviceKind = value
                    case "available":
                        deviceAvailable = (value.lowercased() == "true")
                    default:
                        break
                    }
                }
            }

            if !deviceID.isEmpty && !deviceName.isEmpty {
                let device = [
                    "id": deviceID,
                    "name": deviceName,
                    "active": deviceActive,
                    "volume": deviceVolume,
                    "kind": deviceKind,
                    "available": deviceAvailable
                ] as [String: Any]
                devices.append(device)
            }
        }

        // Check if devices changed
        let deviceHash = devices.map { "\($0["id"] as? String ?? ""):\($0["active"] as? Bool ?? false):\($0["volume"] as? Int ?? 0)" }.sorted().joined(separator: "|")
        if await stateTracker.hasChanged("airplay_devices", newValue: deviceHash) {
            let change = StateChange(type: "airplay_devices", data: ["devices": devices])
            changeHandler?(change)
            print("AirPlay devices changed: \(devices.count) devices")
        }
    }
}

// Parse AppleScript data helper (if needed)
func parseAppleScriptData(_ output: String) -> Data? {
    // Fallback implementation for edge cases
    let hexPattern = try? NSRegularExpression(pattern: "([0-9a-fA-F]{2})", options: [])
    let nsString = output as NSString
    let matches = hexPattern?.matches(in: output, options: [], range: NSRange(location: 0, length: nsString.length))

    if let matches = matches, !matches.isEmpty {
        var data = Data()
        for match in matches.prefix(1024 * 1024) {
            let byteRange = match.range(at: 1)
            if byteRange.location != NSNotFound,
               let hexString = nsString.substring(with: byteRange) as String?,
               let byte = UInt8(hexString, radix: 16) {
                data.append(byte)
            }
        }
        if !data.isEmpty {
            return data
        }
    }

    // Check if it's already valid image data
    if let data = output.data(using: .utf8), data.count > 100 {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return data
        }
    }

    return nil
}
