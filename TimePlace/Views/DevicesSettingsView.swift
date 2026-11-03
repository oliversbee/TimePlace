import SwiftUI

struct DevicesSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var manager: HouseholdManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State private var selectedDevice: PairedDevice?

    var body: some View {
        Form {
            if let error = manager.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("My Frames") {
                if manager.pairedDevices.isEmpty && !manager.isLoading {
                    Text("No paired frames yet.").foregroundColor(.gray)
                } else {
                    ForEach(manager.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name.isEmpty ? "E-Paper Display" : device.name)
                                    .fontWeight(.semibold)

                                Text("ID: \(device.deviceId)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button("Configure") {
                                selectedDevice = device
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("Frame")
        .sheet(item: $selectedDevice) { (device: PairedDevice) in
            DisplayConfigView(device: device)
                .environmentObject(auth)
                .environmentObject(settingsViewModel)
        }
    }
}