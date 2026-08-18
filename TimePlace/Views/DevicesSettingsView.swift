import SwiftUI

struct DevicesSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var manager = HouseholdManager()
    @State private var deviceClaimCode = ""
    @State private var selectedDevice: PairedDevice?

    var body: some View {
        Form {
            if let error = manager.errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("My Displays") {
                if manager.pairedDevices.isEmpty && !manager.isLoading {
                    Text("No paired displays yet.").foregroundColor(.gray)
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

            Section("Pair New Display") {
                TextField("6-character display code", text: $deviceClaimCode)
                    .autocapitalize(.allCharacters)
                
                Button("Link Device") {
                    Task {
                        if await manager.pairDevice(claimCode: deviceClaimCode) {
                            deviceClaimCode = ""
                            await manager.fetchPairedDevices()
                        }
                    }
                }
                .disabled(deviceClaimCode.isEmpty || manager.isLoading)
            }
        }
        .navigationTitle("Devices")
        .sheet(item: $selectedDevice) { (device: PairedDevice) in
            DisplayConfigView(device: device)
                .environmentObject(auth)
        }
        .task {
            await manager.fetchPairedDevices()
        }
    }
}