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
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(serverViewModel)
                .frame(minWidth: 400, minHeight: 300)
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

    private var server: MusicServer?

    init() {
        // Load saved settings
        let settings = SettingsManager.shared.get()
        port = String(settings.port)
        checkLoginItems()
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
            }
        } else {
            // Fallback for older macOS versions - not implemented for simplicity
            print("Login items not supported on this macOS version")
        }
    }

    func checkLoginItems() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: "com.chrissilvertooth.CortlandCastServer")
            addToLoginItems = service.status == .enabled
        }
    }
}
