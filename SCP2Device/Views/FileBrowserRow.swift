import SwiftUI
import UniformTypeIdentifiers

/// A row containing a label, the selected file path, a history menu, and a Browse… button.
/// Also accepts files dropped anywhere onto the row (via an AppKit drop catcher
/// overlay because SwiftUI's `.onDrop` is unreliable on macOS 26).
struct FileBrowserRow: View {
    @Bindable var session: DeviceSession
    @State private var isTargeted = false

    var body: some View {
        LabeledContent("Build Image") {
            HStack {
                // Drop zone + path display
                HStack(spacing: 6) {
                    if isTargeted {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(session.buildPath.isEmpty
                         ? "No file selected  —  drag a file here or use Browse…"
                         : session.buildPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(session.buildPath.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.15)
                              : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1,
                                                       dash: isTargeted ? [6, 3] : [])
                                )
                        )
                )
                // AppKit drop catcher — reliable on macOS 26.
                .overlay(
                    FileDropCatcher(isTargeted: $isTargeted) { url in
                        session.setBuildPath(from: url)
                    }
                )

                // History menu
                if !session.buildPathHistory.isEmpty {
                    Menu {
                        ForEach(session.buildPathHistory, id: \.self) { path in
                            Button {
                                session.buildPath = path
                            } label: {
                                Text((path as NSString).lastPathComponent)
                                    .help(path)
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            session.buildPathHistory = []
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Recent build files")
                }

                Button("Browse…") {
                    chooseFile()
                }.controlSize(.small)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Build Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if !session.buildPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: session.buildPath)
                .deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            session.buildPath = url.path
        }
    }
}
