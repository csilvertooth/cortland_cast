import SwiftUI
import CortlandCastServerCore

struct ContentView: View {
    @EnvironmentObject var viewModel: ServerViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Cortland Cast Server")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Server Status")
                    .font(.headline)

                HStack {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(viewModel.statusMessage)
                        .foregroundColor(viewModel.isRunning ? .green : .red)
                }
            }
            .padding(.horizontal)

            // Port Configuration
            VStack(alignment: .leading, spacing: 10) {
                Text("Port Configuration")
                    .font(.headline)

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
            }
            .padding(.horizontal)

            // Control Buttons
            HStack(spacing: 20) {
                Button(action: {
                    Task {
                        if viewModel.isRunning {
                            await viewModel.stopServer()
                        } else {
                            await viewModel.startServer()
                        }
                    }
                }) {
                    Text(viewModel.isRunning ? "Stop Server" : "Start Server")
                        .frame(width: 120)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .red : .green)
            }

            // Login Items Toggle
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $viewModel.addToLoginItems)
                    .onChange(of: viewModel.addToLoginItems) { newValue in
                        viewModel.toggleLoginItems(newValue)
                    }

                Text("When enabled, the server will automatically start when you log in to your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ServerViewModel())
    }
}
