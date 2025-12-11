//
//  App.swift
//  CortlandCastServer
//
//  Created by Chris Silvertooth on 12/3/2025.
//

import SwiftUI
import ServiceManagement
import CortlandCastServerCore
import Foundation

@main
struct CortlandCastServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var serverViewModel = ServerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverViewModel)
                .frame(minWidth: 500, minHeight: 450)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(serverViewModel)
                .frame(minWidth: 500, minHeight: 450)
        }
    }

    init() {
        // Let the app delegate access the view model
        appDelegate.configure(serverViewModel: serverViewModel)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var serverViewModel: ServerViewModel?

    func configure(serverViewModel: ServerViewModel) {
        self.serverViewModel = serverViewModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check login items on startup
        serverViewModel?.checkLoginItems()

        // Auto-start the server when the app opens (not just from login items)
        Task {
            await serverViewModel?.autoStartServer()

            // Add a small delay then check status again to ensure UI updates
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                serverViewModel?.objectWillChange.send()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure server is stopped when app quits
        if let viewModel = serverViewModel {
            Task {
                await viewModel.stopServer()
            }
            // Clean up timers
            viewModel.cleanupTimers()
        }
    }
}

class ServerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var port: String = "7766"
    @Published var statusMessage = "Server stopped"
    @Published var addToLoginItems = false
    @Published var updateAvailable: GitHubRelease?
    @Published var isCheckingForUpdates = false

    private var server: MusicServer?
    private var updateCheckTimer: Timer?
    private var statusCheckTimer: Timer?

    init() {
        // Load saved settings
        let settings = SettingsManager.shared.get()
        port = String(settings.port)
        checkLoginItems()

        // Start periodic update checking
        startPeriodicUpdateCheck()

        // Start periodic server status checking
        startPeriodicStatusCheck()
    }

    func startPeriodicStatusCheck() {
        // Check server status every 2 seconds to keep UI in sync
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkServerStatus()
        }
    }

    func checkServerStatus() {
        let portNumber = Int(port) ?? 7766
        
        // Always ping the server to get the true status - most reliable method
        let urlString = "http://localhost:\(portNumber)/status"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                if self.isRunning {
                    self.isRunning = false
                    self.statusMessage = "Server stopped"
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0 // Short timeout for status check

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let serverResponding = (response as? HTTPURLResponse)?.statusCode == 200
                
                // Update status based on actual server response
                if serverResponding != self.isRunning {
                    self.isRunning = serverResponding
                    if serverResponding {
                        self.statusMessage = "Server running on port \(portNumber)"
                    } else {
                        self.statusMessage = "Server stopped"
                    }
                }
            }
        }.resume()
    }

    func startServer() async {
        guard let portNumber = Int(port), portNumber > 0 && portNumber < 65536 else {
            await MainActor.run {
                statusMessage = "Invalid port number"
                isRunning = false
            }
            return
        }

        await MainActor.run {
            statusMessage = "Starting server..."
            isRunning = false
        }

        do {
            server = MusicServer()
            try await server?.start(port: portNumber)
            print("Server task created, waiting for startup...")

            // Wait a bit longer to ensure the server is fully ready, then check via ping
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds to let server start up

            // Check server status via HTTP ping to be sure it's responding
            let urlString = "http://localhost:\(portNumber)/status"
            if let url = URL(string: urlString) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 2.0

                let response = try? await URLSession.shared.data(for: request)
                let serverResponding = (response?.1 as? HTTPURLResponse)?.statusCode == 200

                await MainActor.run {
                    isRunning = serverResponding
                    if serverResponding {
                        statusMessage = "Server running on port \(portNumber)"
                        print("Server confirmed running after ping check")
                    } else {
                        statusMessage = "Server started but not responding"
                        print("Server started but failed ping check")
                    }
                }
            } else {
                await MainActor.run {
                    if server?.running ?? false {
                        isRunning = true
                        statusMessage = "Server running on port \(portNumber)"
                    } else {
                        isRunning = false
                        statusMessage = "Server failed to start"
                    }
                }
            }
        } catch {
            await MainActor.run {
                isRunning = false
                statusMessage = "Failed to start server: \(error.localizedDescription)"
            }
        }
    }

    func stopServer() async {
        await MainActor.run {
            statusMessage = "Stopping server..."
        }

        await server?.stop()
        server = nil

        await MainActor.run {
            isRunning = false
            statusMessage = "Server stopped"
        }
    }

    func updatePort(_ newPort: String) {
        port = newPort
        if let portNumber = Int(newPort) {
            var settings = SettingsManager.shared.get()
            settings.port = portNumber
            SettingsManager.shared.update(settings)
        }
    }

    func toggleLoginItems(_ enabled: Bool) {
        addToLoginItems = enabled

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.loginItem(identifier: "com.chrissilvertooth.CortlandCastServer").register()
                } else {
                    try SMAppService.loginItem(identifier: "com.chrissilvertooth.CortlandCastServer").unregister()
                }
            } catch {
                print("Failed to update login items: \(error)")
                // Reset the toggle if the operation failed
                DispatchQueue.main.async {
                    self.addToLoginItems = !enabled
                }
            }
        } else {
            // For older macOS versions, show instructions to manually add to Login Items
            if enabled {
                showLoginItemsInstructions()
            }
        }
    }

    func showLoginItemsInstructions() {
        let alert = NSAlert()
        alert.messageText = "Manual Login Items Setup Required"
        alert.informativeText = "On macOS versions before 13.0, you need to manually add Cortland Cast Server to your Login Items:\n\n1. Go to System Preferences > Users & Groups\n2. Click your user account\n3. Click the Login Items tab\n4. Click the + button\n5. Navigate to and select Cortland Cast Server.app\n\nAlternatively, upgrade to macOS 13.0 or later for automatic setup."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Users & Groups
            if let url = URL(string: "x-apple.systempreferences:com.apple.usersgroups") {
                NSWorkspace.shared.open(url)
            }
        }

        // Reset the toggle since we can't automatically enable it
        DispatchQueue.main.async {
            self.addToLoginItems = false
        }
    }

    func checkLoginItems() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: "com.chrissilvertooth.CortlandCastServer")
            addToLoginItems = service.status == .enabled
        }
    }

    func startPeriodicUpdateCheck() {
        // Check for updates every 6 hours (21600 seconds)
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }

        // Also check immediately on startup
        checkForUpdates()
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else {
            print("Update check already in progress")
            return
        }

        print("Starting manual update check...")

        Task {
            await MainActor.run {
                isCheckingForUpdates = true
                print("Set isCheckingForUpdates = true")
            }

            let release = await VersionManager.shared.checkForUpdates()

            await MainActor.run {
                updateAvailable = release
                isCheckingForUpdates = false
                print("Update check completed. Release: \(release?.version.stringValue ?? "none")")
            }
        }
    }

    func openGitHubRepo() {
        if let url = URL(string: "https://github.com/csilvertooth/cortland_cast") {
            NSWorkspace.shared.open(url)
        }
    }

    func autoStartServer() async {
        // Auto-start the server when the app opens
        if !isRunning {
            await startServer()
        }
    }

    func openConfigFolder() {
        let configDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/CortlandCastServer")

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create config directory: \(error)")
            return
        }

        NSWorkspace.shared.open(configDirectory)
    }

    func cleanupTimers() {
        statusCheckTimer?.invalidate()
        updateCheckTimer?.invalidate()
    }
}
