import Foundation
import ScriptingBridge
import Vapor

// Helper function for generating artwork token (using album name to avoid duplicates)
func generateArtworkToken(title: String?, artist: String?, album: String?) -> String {
    let albumName = album ?? "no_album"
    // Sanitize album name same way as album_artwork endpoint, ensure non-empty
    let sanitized = albumName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    return sanitized.isEmpty ? "no_album" : sanitized
}

// Helper function for reliable repeat mode detection
func getRepeatModeFromAppleScript() -> String {
    let result = runAppleScript("""
    tell application "Music"
        try
            return (song repeat) as text
        on error
            return "off"
        end try
    end tell
    """)
    return result.success ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : "off"
}

struct NowPlaying: Codable, Content {
    var state: String = "unknown"
    var title: String? = nil
    var artist: String? = nil
    var album: String? = nil
    var pid: String? = nil
    var position: Double = 0.0
    var isPlaying: Bool? = nil
    var shuffle: Bool? = nil
    var repeatMode: String? = "off" // off, one, all
    var volume: Int? = nil
    var duration: Double = 0.0
    var artworkToken: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case state, title, artist, album, pid, position, isPlaying = "is_playing",
             shuffle, repeatMode = "repeat", volume, duration, artworkToken = "artwork_token"
    }
}

func getNowPlaying() -> NowPlaying {
    // Try ScriptingBridge first for better performance
    if let sbResult = getNowPlayingScriptingBridge() {
        return sbResult
    } else {
        // Fall back to AppleScript if ScriptingBridge fails
        return getNowPlayingAppleScript()
    }
}

func getNowPlayingScriptingBridge() -> NowPlaying? {
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return nil
    }

    // Use Key-Value Coding to access properties dynamically
    guard let playerState = music.value(forKey: "playerState") as? NSNumber else {
        return nil // Fall back to AppleScript
    }

    let state: String = {
        switch playerState.intValue {
        case 0x6B505350: return "playing"     // 'kPSP'
        case 0x6B505370: return "paused"      // 'kPSp'
        case 0x6B505353: return "stopped"     // 'kPSS'
        default: return "unknown"
        }
    }()

    // If state is unknown, fall back to AppleScript
    guard state != "unknown" else { return nil }

    let currentTrack = music.value(forKey: "currentTrack") as? NSObject
    let title = currentTrack?.value(forKey: "name") as? String
    let artist = currentTrack?.value(forKey: "artist") as? String
    let album = currentTrack?.value(forKey: "album") as? String

    // Position and duration are Doubles
    let position = (music.value(forKey: "playerPosition") as? NSNumber)?.doubleValue ?? 0.0
    let duration = (currentTrack?.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0.0

    // Shuffle and repeat use NSNumber boolean or enum values
    let shuffle = (music.value(forKey: "shuffleEnabled") as? NSNumber)?.boolValue

    // Use AppleScript for reliable repeat mode detection
    let repeatMode = getRepeatModeFromAppleScript()

    let volume = (music.value(forKey: "soundVolume") as? NSNumber)?.intValue ?? 0
    let isPlaying = state.lowercased().contains("play")

    // Generate artwork token
    let artworkToken = generateArtworkToken(title: title, artist: artist, album: album)

    return NowPlaying(
        state: state,
        title: title,
        artist: artist,
        album: album,
        pid: "",
        position: position,
        isPlaying: isPlaying,
        shuffle: shuffle,
        repeatMode: repeatMode,
        volume: volume,
        duration: duration,
        artworkToken: artworkToken
    )
}

func getNowPlayingAppleScript() -> NowPlaying {
    let script = """
    tell application "Music"
        set pstate to player state as text
        set shuf to false
        try
            set shuf to shuffle enabled
        end try
        set rep to song repeat
        set vol to 0
        try
            set vol to sound volume
        end try
        if pstate is "stopped" then
            return pstate & "\\n" & "" & "\\n" & "" & "\\n" & "" & "\\n" & "0" & "\\n" & (shuf as text) & "\\n" & (rep as text) & "\\n" & (vol as text) & "\\n" & "0"
        end if
        set nm to ""
        set ar to ""
        set al to ""
        set pos to 0
        set dur to 0
        try
            set pos to player position
        end try
        try
            set t to current track
        on error
            set t to missing value
        end try
        if t is not missing value then
            try
                set nm to (name of t as text)
            end try
            try
                set ar to (artist of t as text)
            end try
            try
                set al to (album of t as text)
            end try
            try
                set dur to (duration of t)
            end try
        end if
        return pstate & "\\n" & nm & "\\n" & ar & "\\n" & al & "\\n" & (pos as text) & "\\n" & (shuf as text) & "\\n" & (rep as text) & "\\n" & (vol as text) & "\\n" & (dur as text)
    end tell
    """
    
    let result = runAppleScript(script)
    if !result.success {
        return NowPlaying()
    }

    let lines = result.output.components(separatedBy: .newlines)
    guard lines.count >= 9 else {
        return NowPlaying()
    }

    let state = lines[0]
    // Log the AppleScript player state to debug
    print("AppleScript now_playing: state='\(state)', title='\(lines[1])'")
    let title = lines[1].isEmpty ? nil : lines[1]
    let artist = lines[2].isEmpty ? nil : lines[2]
    let album = lines[3].isEmpty ? nil : lines[3]
    let position = Double(lines[4]) ?? 0.0
    let shuffle = Bool(lines[5])
    let repeatMode = lines[6].isEmpty ? "off" : lines[6]
    let volume = Int(lines[7])
    let duration = Double(lines[8]) ?? 0.0
    
    let isPlaying = state.lowercased().contains("play")

    // Generate artwork token
    let artworkToken = generateArtworkToken(title: title, artist: artist, album: album)

    return NowPlaying(
        state: state,
        title: title,
        artist: artist,
        album: album,
        pid: "",
        position: position,
        isPlaying: isPlaying,
        shuffle: shuffle,
        repeatMode: repeatMode,
        volume: volume,
        duration: duration,
        artworkToken: artworkToken
    )
}
