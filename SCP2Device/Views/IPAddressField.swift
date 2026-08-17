import SwiftUI

/// A text field for the device IP address with a dropdown of previously used addresses.
struct IPAddressField: View {
    @Bindable var session: DeviceSession

    var body: some View {
        LabeledContent("Device IP") {
            HStack {
                TextField("e.g. 192.168.1.100", text: $session.ipAddress)
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

                if !session.ipAddressHistory.isEmpty {
                    Menu {
                        ForEach(session.ipAddressHistory, id: \.self) { ip in
                            Button(ip) {
                                session.ipAddress = ip
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            session.ipAddressHistory = []
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
