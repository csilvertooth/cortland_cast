//
//  App.swift
//  CortlandCastServer
//
//  Created by Chris Silvertooth on 12/3/2025.
//

import SwiftUI
import ServiceManagement
import CortlandCastServerCore

@main
struct CortlandCastServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var serverViewModel = ServerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverViewModel)
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(serverViewModel)
                .frame(minWidth: 500, minHeight: 400)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure server is stopped when app quits
        if let viewModel = serverViewModel {
            Task {
                await viewModel.stopServer()
            }
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

    init() {
        // Load saved settings
        let settings = SettingsManager.shared.get()
        port = String(settings.port)
        checkLoginItems()

        // Start periodic update checking
        startPeriodicUpdateCheck()
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

            // Check if server is actually running
            await MainActor.run {
                if server?.running ?? false {
                    isRunning = true
                    statusMessage = "Server running on port \(portNumber)"
                } else {
                    isRunning = false
                    statusMessage = "Server failed to start"
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
}
