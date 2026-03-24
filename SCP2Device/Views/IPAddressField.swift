import SwiftUI

/// A text field for the device IP address with a dropdown of previously used addresses.
struct IPAddressField: View {
    @Bindable var viewModel: InstallViewModel

    var body: some View {
        LabeledContent("Device IP") {
            HStack {
                TextField("e.g. 192.168.1.100", text: $viewModel.ipAddress)
                    .textFieldStyle(.roundedBorder)

                if !viewModel.ipAddressHistory.isEmpty {
                    Menu {
                        ForEach(viewModel.ipAddressHistory, id: \.self) { ip in
                            Button(ip) {
                                viewModel.ipAddress = ip
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            viewModel.ipAddressHistory = []
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Recent IP addresses")
                }
            }
        }
    }
}
