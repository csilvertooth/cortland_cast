import SwiftUI
import CortlandCastServerCore

struct SettingsView: View {
    @EnvironmentObject var viewModel: ServerViewModel

    var body: some View {
        Form {
            Section(header: Text("Server Configuration")) {
                HStack {
                    Text("Default Port:")
                    TextField("", text: $viewModel.port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: viewModel.port) { newValue in
                            if let portNum = Int(newValue), portNum > 0 && portNum < 65536 {
                                viewModel.updatePort(newValue)
                            } else if !newValue.isEmpty {
                                viewModel.port = String(SettingsManager.shared.get().port)
                            }
                        }
                }
            }



            Section(header: Text("About")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cortland Cast Server")
                        .font(.headline)

                    Text("Version: \(VersionManager.shared.getCurrentVersion().stringValue)")
                        .font(.caption)

                    Text("This server provides HTTP API endpoints for controlling Apple's Music app via Home Assistant.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("View API Documentation", destination: URL(string: "http://localhost:\(viewModel.port)/ui")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(ServerViewModel())
    }
}
