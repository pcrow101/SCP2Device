//
//  ContentView.swift
//  SCP2Device
//
//  Created by paucrow on 19/03/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = InstallViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // --- Inputs group ---
            VStack(alignment: .leading, spacing: 12) {
                FileBrowserRow(viewModel: viewModel)
                IPAddressField(viewModel: viewModel)
                LabeledContent("Destination") {
                    TextField("/tmp", text: $viewModel.destinationFolder)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
            .glassEffect(in: RoundedRectangle(cornerRadius: 12))

            // --- Action buttons ---
            HStack(spacing: 8) {
                Button(viewModel.activeAction == .install ? "Cancel" : "Install Build") {
                    viewModel.installBuild()
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.activeAction == .install ? .red : .accentColor)
                .disabled(viewModel.isRunning && viewModel.activeAction != .install)
                .help(viewModel.activeAction == .install
                      ? "Cancel the current install"
                      : "Transfer the build via SCP, flash it, then reboot the device")

                if viewModel.isRunning {
                    if let pct = viewModel.transferProgress {
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

                Button(viewModel.activeAction == .download ? "Cancel" : "Download Only") {
                    viewModel.downloadBuild()
                }
                .controlSize(.small)
                .tint(viewModel.activeAction == .download ? .red : nil)
                .disabled(viewModel.isRunning && viewModel.activeAction != .download)
                .help(viewModel.activeAction == .download
                      ? "Cancel the current download"
                      : "SCP the selected build file onto the device only")

                Button("Flash Only") {
                    viewModel.flashAppOnly()
                }
                .controlSize(.small)
                .disabled(viewModel.isRunning)
                .help("SSH to the device and run FlashApp (build must already be on device)")

                Button("Reboot Device") {
                    viewModel.rebootOnly()
                }
                .controlSize(.small)
                .disabled(viewModel.isRunning)
                .help("SSH to the device and run reboot")

                Spacer()

                Button("Clear Log") {
                    viewModel.clearLog()
                }
                .controlSize(.small)
                .disabled(viewModel.isRunning)
            }
            .padding(.horizontal, 4)

            // --- Progress log ---
            ProgressLogView(text: viewModel.progressLog)
                .frame(minHeight: 200)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 520)
    }
}

#Preview {
    ContentView()
}
