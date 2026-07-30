import SwiftUI

struct ConfigEditorView: View {
    @Bindable var viewModel: InstallViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingSnippet: ConfigSnippet?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            header

            HSplitView {
                snippetPalette
                    .frame(minWidth: 220, idealWidth: 260)

                configEditor
                    .frame(minWidth: 340)
            }

            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            // Always fetch an up-to-date copy of the config from the device
            // when the editor is opened. The method self-validates the IP.
            viewModel.loadConfigFromDevice()
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorSheet(value: snippet.value) { value in
                var updated = snippet
                updated.value = value
                viewModel.updateSnippet(updated)
            }
        }
        .sheet(isPresented: $isCreating) {
            SnippetEditorSheet(value: "") { value in
                viewModel.addSnippet(value: value)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Edit /opt/aamp.cfg", systemImage: "doc.badge.gearshape")
                .font(.headline)
            Spacer()
            Text(viewModel.ipAddress.isEmpty ? "No device IP" : "root@\(viewModel.ipAddress)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var snippetPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Settings Palette")
                    .font(.subheadline).bold()
                Spacer()
                Button {
                    viewModel.appendAllSnippets()
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.configSnippets.isEmpty)
                .help("Add all values to the config")
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new config value")
            }
            .padding(.horizontal, 8)

            Text("Click ⊕ to add a value to the config • drag ≡ to reorder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            List {
                ForEach(viewModel.configSnippets) { snippet in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(snippet.value)
                            .font(.body.monospaced())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            viewModel.appendSnippet(snippet)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Add this value to the config")
                        Button {
                            editingSnippet = snippet
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit this value")
                        Button {
                            viewModel.deleteSnippet(snippet)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Delete this value")
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Add to Config") { viewModel.appendSnippet(snippet) }
                        Button("Edit…") { editingSnippet = snippet }
                        Divider()
                        Button("Delete", role: .destructive) { viewModel.deleteSnippet(snippet) }
                    }
                }
                .onMove { viewModel.moveSnippet(from: $0, to: $1) }
                .onDelete { viewModel.deleteSnippets(at: $0) }
            }
        }
        .padding(.vertical, 8)
    }

    private var configEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Config Contents")
                .font(.subheadline).bold()
                .padding(.horizontal, 8)

            TextEditor(text: $viewModel.configText)
                .font(.body.monospaced())
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Load from Device") { viewModel.loadConfigFromDevice() }
                .disabled(viewModel.isRunning)
            Button("Save to Device") { viewModel.saveConfigToDevice() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning)

            if viewModel.isRunning {
                ProgressView().controlSize(.small)
            }

            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

/// Small sheet for creating / editing a single config value.
private struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Config Value").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Value")
                TextEditor(text: $value)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
