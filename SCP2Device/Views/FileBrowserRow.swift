import SwiftUI
import UniformTypeIdentifiers

/// A row containing a label, the selected file path, a history menu, and a Browse… button.
/// Also accepts files dropped anywhere onto the row (via an AppKit drop catcher
/// overlay because SwiftUI's `.onDrop` is unreliable on macOS 26).
struct FileBrowserRow: View {
    @Bindable var viewModel: InstallViewModel
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
                    Text(viewModel.buildPath.isEmpty
                         ? "No file selected  —  drag a file here or use Browse…"
                         : viewModel.buildPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(viewModel.buildPath.isEmpty ? .secondary : .primary)
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
                        applyDroppedURL(url)
                    }
                )

                // History menu
                if !viewModel.buildPathHistory.isEmpty {
                    Menu {
                        ForEach(viewModel.buildPathHistory, id: \.self) { path in
                            Button {
                                viewModel.buildPath = path
                            } label: {
                                Text((path as NSString).lastPathComponent)
                                    .help(path)
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            viewModel.buildPathHistory = []
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

    private func applyDroppedURL(_ url: URL) {
        let path = url.isFileURL ? url.path : url.absoluteString
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        guard exists, !isDir.boolValue else {
            viewModel.appendLog("⚠ Drop ignored: not an existing file (\(path)).\n")
            return
        }
        viewModel.buildPath = path
        viewModel.appendLog("✔ Build file set via drop: \(path)\n")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Build Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if !viewModel.buildPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: viewModel.buildPath)
                .deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.buildPath = url.path
        }
    }
}
