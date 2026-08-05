import SwiftUI

/// A text field for the device IP address with a dropdown of previously used addresses.
struct IPAddressField: View {
    @Bindable var viewModel: InstallViewModel

    var body: some View {
        LabeledContent("Device IP") {
            HStack {
                TextField("e.g. 192.168.1.100", text: $viewModel.ipAddress)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )

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
