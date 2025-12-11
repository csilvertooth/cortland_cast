import SwiftUI
import CortlandCastServerCore
import Foundation
import AppKit

// Import AppleScript utilities from CortlandCastServerCore
// Note: runAppleScript is defined in CortlandCastServerCore/Utils/AppleScriptWrapper.swift

class ServerLogger {
    static let shared = ServerLogger()

    private var logFileURL: URL

    private init() {
        // Setup log file path
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let logsDir = libraryDir?.appendingPathComponent("Logs/CortlandCastServer")
        self.logFileURL = logsDir?.appendingPathComponent("server.log") ?? FileManager.default.temporaryDirectory.appendingPathComponent("cortland_cast_server.log")

        // Ensure logs directory exists
        if let logsDir = logsDir {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
    }

    func log(_ message: String, level: String = "INFO") {
        let timestamp = Date().formatted(.iso8601)
        let formattedMessage = "[\(timestamp)] [\(level)] \(message)\n"

        // Print to console (for Xcode console and system logs)
        print(formattedMessage.trimmingCharacters(in: .whitespacesAndNewlines))

        // Append to log file
        do {
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                let initialContent = """
                == Cortland Cast Server Logs ==
                Server started at \(Date().formatted(.dateTime))
                This view shows the local server activity logs from the macOS Swift application.

                """
                try initialContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            }

            let handle = try FileHandle(forWritingTo: logFileURL)
            handle.seekToEndOfFile()
            if let data = formattedMessage.data(using: .utf8) {
                handle.write(data)
            }
            try handle.close()
        } catch {
            print("Failed to write to log file: \(error)")
        }
    }
}

// File monitoring utility for log files
class FileMonitor {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private let changeHandler: () -> Void

    init?(fileURL: URL, changeHandler: @escaping () -> Void) {
        self.fileURL = fileURL
        self.changeHandler = changeHandler

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
            try fileHandle?.seekToEnd()
            startMonitoring()
        } catch {
            print("Failed to create file monitor: \(error)")
            return nil
        }
    }

    private func startMonitoring() {
        let fileDescriptor = fileHandle?.fileDescriptor ?? -1
        guard fileDescriptor != -1 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            self?.changeHandler()
        }

        source?.activate()
    }

    deinit {
        source?.cancel()
        try? fileHandle?.close()
    }
}

struct DebugLogsView: View {
    @EnvironmentObject var viewModel: ServerViewModel
    @State private var logsText = ""
    @State private var isDebugEnabled = false
    @State private var isTailEnabled = true
    @State private var fileMonitor: FileMonitor?

    var body: some View {
        VStack(spacing: 10) {
            Text("Debug Logs")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status and controls
            HStack(spacing: 20) {
                Toggle("Auto-scroll", isOn: $isTailEnabled)
                    .onChange(of: isTailEnabled) { enabled in
                        if enabled {
                            scrollToBottom()
                        }
                    }

                Button(action: {
                    saveLogsToFile()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Logs")
                    }
                }
                .buttonStyle(.bordered)

                Button(action: {
                    clearLogs()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)

            // Logs display
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(logsText.isEmpty ? "No logs available. Enable logging in Home Assistant integration settings.\n\nNote: This shows logs from the Cortland Cast components, not raw system logs." : logsText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .id("logsContent")
                    }
                }
                .background(Color.black.opacity(0.1))
                .cornerRadius(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    startMonitoringLogs()
                }
                .onDisappear {
                    stopMonitoringLogs()
                }
                .onChange(of: logsText) { _ in
                    if isTailEnabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    private func startMonitoringLogs() {
        // Monitor the actual server log file in the logs directory
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let logsDir = libraryDir?.appendingPathComponent("Logs/CortlandCastServer")
        let logFileURL = logsDir?.appendingPathComponent("server.log") ?? FileManager.default.temporaryDirectory.appendingPathComponent("cortland_cast_server.log")

        // Ensure logs directory exists
        if let logsDir = logsDir {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        // Create initial content if the file doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            let initialContent = """
            == Cortland Cast Server Logs ==
            \(Date().formatted(.dateTime))
            Server logs will appear here when the server is running and logging is active.

            This view shows the local server logs from the macOS Swift application.
            """
            try? initialContent.write(to: logFileURL, atomically: true, encoding: .utf8)
        }

        // Load initial content
        loadLogsFromFile()

        // Start monitoring the log file for changes
        fileMonitor = FileMonitor(fileURL: logFileURL) {
            DispatchQueue.main.async {
                self.loadLogsFromFile()
            }
        }
    }

    private func stopMonitoringLogs() {
        fileMonitor = nil
    }

    private func loadLogsFromFile() {
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let logsDir = libraryDir?.appendingPathComponent("Logs/CortlandCastServer")
        let logFileURL = logsDir?.appendingPathComponent("server.log") ?? FileManager.default.temporaryDirectory.appendingPathComponent("cortland_cast_server.log")

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            DispatchQueue.main.async {
                self.logsText = content
            }
        } catch {
            DispatchQueue.main.async {
                self.logsText = """
                == Cortland Cast Server Logs ==
                \(Date().formatted(.dateTime))
                Server logs will appear here when the server is running and logging is active.

                This view shows the local server logs from the macOS Swift application.
                Error: \(error.localizedDescription)
                """
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy? = nil) {
        proxy?.scrollTo("logsContent", anchor: .bottom)
    }

    private func saveLogsToFile() {
        // Save to proper macOS logs directory
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let logsDir = libraryDir?.appendingPathComponent("Logs/CortlandCastServer")
        
        // Ensure logs directory exists
        if let logsDir = logsDir {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        let timestamp = Date().formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted))
        let filename = "cortland_cast_logs_\(timestamp).log"
        let defaultURL = logsDir?.appendingPathComponent(filename) ?? FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try self.logsText.write(to: defaultURL, atomically: true, encoding: .utf8)
            
            // Show success alert with option to reveal in Finder
            let alert = NSAlert()
            alert.messageText = "Logs Saved"
            alert.informativeText = "Debug logs have been saved to:\n\(defaultURL.path)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show in Finder")
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.selectFile(defaultURL.path, inFileViewerRootedAtPath: "")
            }
            
        } catch {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = "Failed to save logs: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func clearLogs() {
        let alert = NSAlert()
        alert.messageText = "Clear Logs"
        alert.informativeText = "Are you sure you want to clear all logs? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Clear the log file
            let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            let logsDir = libraryDir?.appendingPathComponent("Logs/CortlandCastServer")
            let logFileURL = logsDir?.appendingPathComponent("server.log") ?? FileManager.default.temporaryDirectory.appendingPathComponent("cortland_cast_server.log")

            let clearedContent = """

            == Cortland Cast Server Logs Cleared ==
            Logs cleared at \(Date().formatted(.dateTime))

            """
            try? clearedContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            loadLogsFromFile()
        }
    }
}

// Window controller for Tools window
class ToolsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Music Tools"
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
    }
}

// Tools View for Music Management
struct ToolsView: View {
    @State private var isDownloadingMusic = false
    @State private var isCheckingProtectedFiles = false
    @State private var isBackingUpFiles = false
    @State private var toolStatus = ""
    @State private var protectedFilesCount = 0
    @State private var downloadProgress = ""
    @State private var macOSVersion = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Music Tools")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Divider()
                
                // Download All Music Tool
                VStack(alignment: .leading, spacing: 10) {
                    Text("Download All Cloud Music")
                        .font(.headline)

                    Text("Download all iCloud music to this Mac for local playback and proper Artwork being displayed in Home Assistant.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("⚠️ Note: Tracks from Apple Music playlists must be downloaded manually.  User created playlists should work.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.vertical, 2)

                    if !macOSVersion.isEmpty {
                        Text(macOSVersion)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.vertical, 4)
                    }

                    if !downloadProgress.isEmpty && isDownloadingMusic {
                        Text(downloadProgress)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Button(action: {
                        downloadAllMusic()
                    }) {
                        HStack {
                            if isDownloadingMusic {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Downloading...")
                            } else {
                                Image(systemName: "icloud.and.arrow.down")
                                Text("Download All Music")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDownloadingMusic)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Check for Protected Files Tool
                VStack(alignment: .leading, spacing: 10) {
                    Text("Check for Protected Music Files")
                        .font(.headline)
                    
                    Text("Scan library for DRM-protected .m4p files and create a \"Protected Music\" playlist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if protectedFilesCount > 0 {
                        Text("Found \(protectedFilesCount) protected files")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Button(action: {
                        checkProtectedFiles()
                    }) {
                        HStack {
                            if isCheckingProtectedFiles {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking...")
                            } else {
                                Image(systemName: "lock.shield")
                                Text("Check Protected Files")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCheckingProtectedFiles)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Backup Protected Files Tool
                VStack(alignment: .leading, spacing: 10) {
                    Text("Backup Protected Music Files")
                        .font(.headline)
                    
                    Text("Copy all protected .m4p files to ~/Music/ProtectedMusic")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        backupProtectedFiles()
                    }) {
                        HStack {
                            if isBackingUpFiles {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Backing Up...")
                            } else {
                                Image(systemName: "folder.badge.plus")
                                Text("Backup Protected Files")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBackingUpFiles || protectedFilesCount == 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Status Display
                if !toolStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Status:")
                            .font(.headline)
                        Text(toolStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 650, minHeight: 600)
        .onAppear {
            checkMacOSVersion()
        }
    }
    
    private func checkMacOSVersion() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        // macOS 15 = Sequoia
        if osVersion.majorVersion == 15 {
            macOSVersion = "⚠️ Note: Download feature may not work on all versions of Apple Music.  It has been on tested on Sequoia and Tahoe"
        }
    }
    
    private func downloadAllMusic() {
        isDownloadingMusic = true
        downloadProgress = "Finding cloud tracks..."
        toolStatus = "Starting download of all cloud music..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Use a much faster approach: just tell Music to download all cloud tracks
            // without iterating through each one individually
            let script = """
            (*
            Download all cloud-backed tracks from your library and user playlists that are NOT yet downloaded.

            Whitelisted cloud statuses include:
                - subscription (Apple Music enum)
                - matched
                - purchased
                - uploaded
                - Apple Music (literal string)
            
            Behaviour:
                - Scans library playlist 1 and all user playlists in batches.
                - Deduplicates tracks using database ID.
                - Skips tracks that already have a local file.
                - Queues downloads for remaining cloud-backed tracks.
                - Posts a progress notification every 100 tracks processed.
                - Logs details to a timestamped file on the Desktop.
            *)

            property statusWhitelist : {"subscription", "matched", "purchased", "uploaded", "Apple Music"}
            property batchSize : 500    -- number of tracks to process per batch
            property notifyInterval : 100  -- how many tracks between status notifications

            -- Helper: write list of lines to a text file
            on writeLinesToFile(lineList, hfsPath)
                set AppleScript's text item delimiters to linefeed
                set fileText to lineList as text
                set AppleScript's text item delimiters to ""
                
                set f to open for access file hfsPath with write permission
                try
                    set eof of f to 0
                    write fileText to f starting at 0
                end try
                close access f
            end writeLinesToFile

            -- Gather tracks from library and all user playlists
            tell application "Music"
                try
                    set libTracks to every track of library playlist 1
                    set userLists to every user playlist
                    set playlistTracks to {}
                    repeat with pl in userLists
                        try
                            set playlistTracks to playlistTracks & (every track of pl)
                        end try
                    end repeat
                on error errMsg
                    return "ERROR:Failed to get tracks: " & errMsg
                end try
            end tell

            -- Combine and de-duplicate tracks by database ID
            set allTracks to libTracks & playlistTracks
            set processedIDs to {}
            set candidateTracks to {}

            repeat with t in allTracks
                tell application "Music"
                    try
                        set dbid to database ID of t
                        if dbid is not in processedIDs then
                            set end of processedIDs to dbid
                            set csText to (cloud status of t) as text
                            if csText is in statusWhitelist then
                                set end of candidateTracks to t
                            end if
                        end if
                    end try
                end tell
            end repeat

            set totalCandidates to (count of candidateTracks)
            set skippedAlreadyDownloaded to 0
            set queuedDownloads to 0
            set processedCount to 0

            -- Prepare logging
            set logLines to {}
            set end of logLines to "Track | Artist | Album | CloudStatus | HasLocalFile | QueuedDownload"

            -- Process candidates in batches
            tell application "Music"
                repeat with i from 1 to totalCandidates by batchSize
                    set batchEnd to (i + batchSize - 1)
                    if batchEnd > totalCandidates then set batchEnd to totalCandidates
                    
                    set batchTracks to items i thru batchEnd of candidateTracks
                    
                    repeat with t in batchTracks
                        set processedCount to processedCount + 1
                        
                        try
                            set trackName to ""
                            set artistName to ""
                            set albumName to ""
                            
                            try
                                set trackName to name of t
                            end try
                            try
                                set artistName to artist of t
                            end try
                            try
                                set albumName to album of t
                            end try
                            
                            set csText to (cloud status of t) as text
                            -- detect local file (use both downloaded flag and location property)
                            set hasLocal to false
                            try
                                if downloaded of t is true then set hasLocal to true
                            end try
                            try
                                set trackLoc to location of t
                                if trackLoc is not missing value then
                                    set hasLocal to true
                                end if
                            end try
                            
                            set queuedFlag to "no"
                            
                            if hasLocal then
                                set skippedAlreadyDownloaded to skippedAlreadyDownloaded + 1
                            else
                                try
                                    download t
                                    set queuedDownloads to queuedDownloads + 1
                                    set queuedFlag to "yes"
                                on error
                                    set queuedFlag to "error"
                                end try
                            end if
                            
                            set end of logLines to (trackName & " | " & artistName & " | " & albumName & " | " & csText & " | " & (hasLocal as text) & " | " & queuedFlag)
                        end try
                        
                        -- Post a status notification every `notifyInterval` tracks
                        if (processedCount mod notifyInterval) = 0 then
                            display notification "Processed " & processedCount & " of " & totalCandidates & " tracks so far (" & queuedDownloads & " queued, " & skippedAlreadyDownloaded & " skipped)." with title "Apple Music Download Progress"
                        end if
                    end repeat
                    
                    delay 0.2  -- brief pause between batches
                end repeat
            end tell

            -- Write log file
            set timeStamp to do shell script "date +%Y%m%d-%H%M%S"
            set logFileName to "CloudDownloads-" & timeStamp & ".txt"
            set desktopPath to (path to desktop as text) & logFileName
            my writeLinesToFile(logLines, desktopPath)

            display dialog ("Cloud download pass complete." & return & return & ¬
                "Cloud candidates (library + playlists): " & totalCandidates & return & ¬
                "Already downloaded (skipped): " & skippedAlreadyDownloaded & return & ¬
                "Queued for download: " & queuedDownloads & return & ¬
                "Log saved as: " & logFileName) buttons {"OK"} default button 1

            return "SUCCESS:" & totalCandidates & ":" & queuedDownloads
            """
            
            let result = runAppleScript(script)
            
            DispatchQueue.main.async {
                isDownloadingMusic = false
                downloadProgress = ""
                if result.success && result.output.hasPrefix("SUCCESS:") {
                    let total = result.output.replacingOccurrences(of: "SUCCESS:", with: "")
                    toolStatus = "Found \(total) cloud tracks and initiated downloads. Music app will download them in the background. Check Music app's download progress indicator."
                } else if result.success && result.output.hasPrefix("ERROR:") {
                    toolStatus = "Error: \(result.output.replacingOccurrences(of: "ERROR:", with: ""))"
                } else {
                    toolStatus = "Error: \(result.error.isEmpty ? result.output : result.error)"
                }
            }
        }
    }
    
    private func checkProtectedFiles() {
        isCheckingProtectedFiles = true
        toolStatus = "Checking for protected music files..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            tell application "Music"
                try
                    -- Check for all .m4p files in library
                    set protectedTracks to every track of library playlist 1 whose kind contains "protected"
                    set protectedCount to count of protectedTracks
                    
                    if protectedCount is 0 then
                        return "NONE_FOUND"
                    end if
                    
                    -- Create or update Protected Music playlist
                    set playlistName to "Protected Music"
                    if not (exists user playlist playlistName) then
                        make new user playlist with properties {name:playlistName}
                    end if
                    set protectedPlaylist to user playlist playlistName
                    
                    -- Clear existing tracks
                    delete every track of protectedPlaylist
                    
                    -- Add protected tracks to playlist
                    repeat with t in protectedTracks
                        duplicate t to protectedPlaylist
                    end repeat
                    
                    return "SUCCESS:" & protectedCount
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """
            
            let result = runAppleScript(script)
            
            DispatchQueue.main.async {
                isCheckingProtectedFiles = false
                if result.success {
                    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if output == "NONE_FOUND" {
                        toolStatus = "No protected music files found in library"
                        protectedFilesCount = 0
                    } else if output.hasPrefix("SUCCESS:") {
                        let countStr = output.replacingOccurrences(of: "SUCCESS:", with: "")
                        protectedFilesCount = Int(countStr) ?? 0
                        toolStatus = "Found \(protectedFilesCount) protected files. Created 'Protected Music' playlist."
                    } else if output.hasPrefix("ERROR:") {
                        toolStatus = "Error: \(output.replacingOccurrences(of: "ERROR:", with: ""))"
                    }
                } else {
                    toolStatus = "Error: \(result.error)"
                }
            }
        }
    }
    
    private func backupProtectedFiles() {
        if protectedFilesCount == 0 {
            toolStatus = "No protected files to backup. Run 'Check Protected Files' first."
            return
        }
        
        isBackingUpFiles = true
        toolStatus = "Backing up \(protectedFilesCount) protected files..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First, get the protected music from the Protected Music playlist
            let script = """
            set backupFolder to (path to music folder as text) & "ProtectedMusic"
            
            tell application "Finder"
                if not (exists folder backupFolder) then
                    make new folder at (path to music folder) with properties {name:"ProtectedMusic"}
                end if
            end tell
            
            tell application "Music"
                try
                    set protectedPlaylist to user playlist "Protected Music"
                    set protectedTracks to every track of protectedPlaylist
                    set copiedCount to 0
                    set errorCount to 0
                    set errorMessages to ""
                    
                    repeat with t in protectedTracks
                        try
                            set trackLocation to location of t
                            if trackLocation is not missing value then
                                tell application "Finder"
                                    set trackFile to trackLocation as alias
                                    set trackName to name of trackFile
                                    set destFolder to folder backupFolder
                                    
                                    -- Check if file already exists in destination
                                    if not (exists file trackName of destFolder) then
                                        duplicate trackFile to destFolder
                                        set copiedCount to copiedCount + 1
                                    else
                                        set copiedCount to copiedCount + 1
                                    end if
                                end tell
                            end if
                        on error errMsg
                            set errorCount to errorCount + 1
                            set errorMessages to errorMessages & errMsg & "; "
                        end try
                    end repeat
                    
                    set backupPath to POSIX path of (backupFolder as text)
                    if errorCount > 0 then
                        return "PARTIAL:" & copiedCount & ":" & backupPath & ":ERRORS:" & errorCount & ":" & errorMessages
                    else
                        return "SUCCESS:" & copiedCount & ":" & backupPath
                    end if
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """
            
            let result = runAppleScript(script)
            
            DispatchQueue.main.async {
                isBackingUpFiles = false
                if result.success {
                    let output = result.output
                    if output.hasPrefix("SUCCESS:") {
                        let parts = output.replacingOccurrences(of: "SUCCESS:", with: "").split(separator: ":")
                        if parts.count >= 2 {
                            let copiedCount = String(parts[0])
                            let backupPath = parts[1...].joined(separator: ":")
                            toolStatus = "Successfully backed up \(copiedCount) files to \(backupPath)"
                        } else {
                            toolStatus = "Backup completed"
                        }
                    } else if output.hasPrefix("PARTIAL:") {
                        let withoutPrefix = output.replacingOccurrences(of: "PARTIAL:", with: "")
                        let parts = withoutPrefix.split(separator: ":ERRORS:")
                        if parts.count >= 1 {
                            let successParts = parts[0].split(separator: ":")
                            if successParts.count >= 2 {
                                let copiedCount = String(successParts[0])
                                let backupPath = successParts[1...].joined(separator: ":")
                                let errorInfo = parts.count > 1 ? String(parts[1]) : "unknown errors"
                                toolStatus = "Backed up \(copiedCount) files to \(backupPath). Some errors occurred: \(errorInfo)"
                            }
                        }
                    } else if output.hasPrefix("ERROR:") {
                        toolStatus = "Error: \(output.replacingOccurrences(of: "ERROR:", with: ""))"
                    } else {
                        toolStatus = "Unexpected result: \(output)"
                    }
                } else {
                    toolStatus = "Error: \(result.error)"
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: ServerViewModel
    @State private var showingLogsView = false
    @State private var toolsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Cortland Cast Server")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status Section
            VStack(spacing: 10) {
                Text("Server Status")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(viewModel.statusMessage)
                        .foregroundColor(viewModel.isRunning ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            // Three column layout for configuration, info, and tools
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Server Configuration
                    VStack(alignment: .center, spacing: 10) {
                        Text("Server Configuration")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .center, spacing: 8) {
                            Text("Port Configuration")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("Port:")
                                TextField("", text: $viewModel.port)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .onChange(of: viewModel.port) { newValue in
                                        // Validate port number
                                        if let portNum = Int(newValue), portNum > 0 && portNum < 65536 {
                                            viewModel.updatePort(newValue)
                                        } else if !newValue.isEmpty {
                                            // Reset to last valid port if invalid
                                            viewModel.port = String(SettingsManager.shared.get().port)
                                        }
                                    }
                            }

                            Button(action: {
                                viewModel.openConfigFolder()
                            }) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("Open Config Folder")
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                    }
                    .frame(width: geometry.size.width / 3 - 13)

                    // Middle Column: Updates & Info
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Updates & Info")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .center, spacing: 8) {
                            Button(action: {
                                viewModel.openGitHubRepo()
                            }) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("View on GitHub")
                                }
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                viewModel.checkForUpdates()
                            }) {
                                if viewModel.isCheckingForUpdates {
                                    HStack(spacing: 5) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Checking...")
                                            .frame(width: 120, alignment: .leading)
                                    }
                                } else {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Check for Updates")
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            if let update = viewModel.updateAvailable {
                                Text("New version: \(update.version.stringValue)")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }

                            Button(action: {
                                showingLogsView = true
                            }) {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("Debug Logs")
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(width: geometry.size.width / 3 - 13)

                    // Right Column: Tools
                    VStack(alignment: .center, spacing: 10) {
                        Text("Tools")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .center, spacing: 8) {
                            Text("Music Management")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button(action: {
                                openToolsWindow()
                            }) {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver")
                                    Text("Open Tools")
                                }
                            }
                            .buttonStyle(.bordered)

                            Text("Download music, check protected files, and more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .frame(width: geometry.size.width / 3 - 13)
                }
                .frame(width: geometry.size.width)
            }
            .padding(.horizontal)

            Spacer()

            // Footer
            VStack(spacing: 5) {
                Text("Home Assistant Integration")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Configure the Home Assistant integration to access the full web interface.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $showingLogsView) {
            DebugLogsView()
                .environmentObject(viewModel)
        }
    }
    
    private func openToolsWindow() {
        // If window exists, just bring it forward
        if let window = toolsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Music Tools"
        window.contentView = NSHostingView(rootView: ToolsView())
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        
        toolsWindow = window
        
        // Activate app to bring window forward
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ServerViewModel())
    }
}
