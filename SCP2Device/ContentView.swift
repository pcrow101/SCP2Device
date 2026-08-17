//
//  ContentView.swift
//  SCP2Device
//
//  Created by paucrow on 19/03/2026.
//

import SwiftUI

struct ContentView: View {
    /// Shared connection settings + progress log.
    @State private var session: DeviceSession

    /// Feature view models, each scoped to one concern.
    @State private var install: InstallViewModel
    @State private var deviceInfo: DeviceInfoViewModel
    @State private var configEditor: ConfigEditorViewModel

    @State private var showConfigEditor = false
    @Environment(\.openWindow) private var openWindow

    init() {
        let session = DeviceSession()
        _session = State(initialValue: session)
        _install = State(initialValue: InstallViewModel(session: session))
        _deviceInfo = State(initialValue: DeviceInfoViewModel(session: session))
        _configEditor = State(initialValue: ConfigEditorViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            inputsCard
            actionButtons

            ProgressLogView(text: session.progressLog)
                .frame(minHeight: 200)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 520)
        // Clicking empty space resigns first responder so TextField focus
        // rings clear when the user clicks away.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        )
        // Formatting build info is a presentation concern, so the view renders
        // the model that the view model publishes. We observe the fetch
        // *count*, not `latestBuildInfo` itself: BuildInfo is Equatable, and
        // onChange(of:) only fires when the value differs, so two identical
        // consecutive fetches (e.g. re-checking an unchanged device) would
        // otherwise silently produce no log output.
        .onChange(of: deviceInfo.buildInfoFetchCount) { _, _ in
            guard let info = deviceInfo.latestBuildInfo else { return }
            session.appendLog(BuildInfoReport.format(info))
        }
        .sheet(isPresented: $showConfigEditor) {
            ConfigEditorView(viewModel: configEditor)
        }
    }

    // MARK: - Sections

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileBrowserRow(session: session)
            IPAddressField(session: session)
            LabeledContent("Destination") {
                TextField("/tmp", text: $session.destinationFolder)
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
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(session.activeAction == .install ? "Cancel" : "Install Build") {
                install.installBuild()
            }
            .buttonStyle(.borderedProminent)
            .tint(session.activeAction == .install ? .red : .accentColor)
            .disabled(session.isRunning && session.activeAction != .install)
            .help(session.activeAction == .install
                  ? "Cancel the current install"
                  : "Transfer the build via SCP, flash it, then reboot the device")

            if session.isRunning {
                if let pct = session.transferProgress {
                    HStack(spacing: 6) {
                        ProgressView(value: pct, total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 140)
                        Text("\(Int(pct))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } else {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer()

            Button(session.activeAction == .download ? "Cancel" : "Download Only") {
                install.downloadBuild()
            }
            .controlSize(.small)
            .tint(session.activeAction == .download ? .red : nil)
            .disabled(session.isRunning && session.activeAction != .download)
            .help(session.activeAction == .download
                  ? "Cancel the current download"
                  : "SCP the selected build file onto the device only")

            Button("Flash Only") {
                install.flashAppOnly()
            }
            .controlSize(.small)
            .disabled(session.isRunning)
            .help("SSH to the device and run FlashApp (build must already be on device)")

            Button("Reboot Device") {
                install.rebootOnly()
            }
            .controlSize(.small)
            .disabled(session.isRunning)
            .help("SSH to the device and run reboot")

            Button("Build Info") {
                deviceInfo.showBuildInfo()
            }
            .controlSize(.small)
            .disabled(session.isRunning)
            .help("SSH to the device and show build/version details in the log")

            Spacer()

            Button("Disable Auto Update") {
                deviceInfo.disableAutoUpdate()
            }
            .controlSize(.small)
            .disabled(session.isRunning)
            .help("Write aisettings.overrides.json to disable dynamic auto-updates on the device")

            Button("Edit AAMP Config…") {
                showConfigEditor = true
            }
            .controlSize(.small)
            .disabled(session.isRunning)
            .help("Edit /opt/aamp.cfg on the device using the settings palette")

            Spacer()

            Button("Clear Log") {
                session.clearLog()
            }
            .controlSize(.small)
            .disabled(session.isRunning)

            Button {
                openWindow(id: "help")
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .help("Show SCP2Device help (⌘?)")
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    ContentView()
}
