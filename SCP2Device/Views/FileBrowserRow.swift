import SwiftUI
import UniformTypeIdentifiers

/// A row containing a label, the selected file path, a history menu, and a Browse… button.
/// Also accepts files dropped anywhere onto the drop zone.
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
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, url.isFileURL else { return }
                        DispatchQueue.main.async {
                            viewModel.buildPath = url.path
                        }
                    }
                    return true
                }

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
