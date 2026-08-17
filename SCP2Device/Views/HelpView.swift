//
//  HelpView.swift
//  SCP2Device
//
//  Searchable in-app help. Presented as a standalone window (Help menu)
//  or a sheet from the main window (? toolbar button).
//

import SwiftUI

// MARK: - Data model

private enum HelpItem: Identifiable {
    case paragraph(String)
    case bullet(String)
    case numbered([String])

    nonisolated var id: String {
        switch self {
        case .paragraph(let s): return "p:" + s
        case .bullet(let s):    return "b:" + s
        case .numbered(let a):  return "n:" + a.joined(separator: "|")
        }
    }

    /// Flat searchable text (markdown syntax stripped so `**word**` matches "word").
    nonisolated var searchText: String {
        switch self {
        case .paragraph(let s): return HelpItem.strip(s)
        case .bullet(let s):    return HelpItem.strip(s)
        case .numbered(let a):  return a.map(HelpItem.strip).joined(separator: " ")
        }
    }

    nonisolated static func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "")
         .replacingOccurrences(of: "`", with: "")
    }
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [HelpItem]
}

// MARK: - View

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private let sections: [HelpSection] = HelpView.buildSections()

    private var filteredSections: [HelpSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sections }
        let lower = q.lowercased()
        return sections.compactMap { section in
            // Section matches wholesale if title matches.
            if section.title.lowercased().contains(lower) { return section }
            // Otherwise keep only matching items.
            let matching = section.items.filter { $0.searchText.lowercased().contains(lower) }
            guard !matching.isEmpty else { return nil }
            return HelpSection(title: section.title, icon: section.icon, items: matching)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()

            if filteredSections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(filteredSections) { section in
                            sectionCard(section)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 700)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Label("SCP2Device Help", systemImage: "questionmark.circle")
                .font(.title2.bold())
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search help…", text: $query)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No results for \u{201C}\(query)\u{201D}")
                .font(.headline)
            Text("Try a different word, e.g. \u{201C}flash\u{201D}, \u{201C}IP\u{201D}, or \u{201C}config\u{201D}.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section rendering

    @ViewBuilder
    private func sectionCard(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.title, systemImage: section.icon)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items) { item in
                    itemView(item)
                }
            }
            .font(.body)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func itemView(_ item: HelpItem) -> some View {
        switch item {
        case .paragraph(let s):
            highlighted(s)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let s):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                highlighted(s)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        case .numbered(let arr):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(arr.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        highlighted(s)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Renders markdown and, when a search query is active, highlights every
    /// case-insensitive occurrence of the query.
    private func highlighted(_ markdown: String) -> Text {
        var attributed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Text(attributed) }

        let plain = String(attributed.characters)
        let lowerPlain = plain.lowercased()
        let lowerQuery = q.lowercased()

        var searchStart = lowerPlain.startIndex
        while searchStart < lowerPlain.endIndex,
              let r = lowerPlain.range(of: lowerQuery, range: searchStart..<lowerPlain.endIndex) {
            let startOffset = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let endOffset   = plain.distance(from: plain.startIndex, to: r.upperBound)

            let aStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let aEnd   = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)
            let range  = aStart..<aEnd

            attributed[range].backgroundColor = .yellow.opacity(0.55)
            attributed[range].foregroundColor = .black

            searchStart = r.upperBound
        }
        return Text(attributed)
    }

    // MARK: - Content

    private static func buildSections() -> [HelpSection] {
        [
            HelpSection(title: "Overview", icon: "info.circle", items: [
                .paragraph("""
                SCP2Device installs new builds onto a streaming device over the \
                network. It handles the full workflow: transferring the build via \
                SCP, flashing it, and rebooting — or you can run each step \
                individually. It also has tools for reading build information, \
                editing the AAMP config, and disabling dynamic auto-updates.
                """)
            ]),

            HelpSection(title: "Quick Start", icon: "bolt.fill", items: [
                .numbered([
                    "Drag a build file into the **Build Image** field, or click **Browse…**",
                    "Enter the device's IP address in **Device IP** (or pick a previous one from the history menu).",
                    "Leave **Destination** as `/tmp` unless you know you need somewhere else.",
                    "Click **Install Build** to transfer, flash, and reboot in one step. Watch progress in the log at the bottom."
                ])
            ]),

            HelpSection(title: "Fields", icon: "text.cursor", items: [
                .bullet("**Build Image** — the local build file to install. Supports drag-and-drop from Finder. A history menu remembers the last 10 builds."),
                .bullet("**Device IP** — IPv4 address of the target device. History menu remembers the last 10."),
                .bullet("**Destination** — remote folder for the build. Defaults to `/tmp`. Llama devices automatically get a trailing space appended for the flash step.")
            ]),

            HelpSection(title: "Buttons", icon: "square.grid.2x2", items: [
                .bullet("**Install Build** — full workflow: SCP → FlashApp → reboot. Press again while running to cancel."),
                .bullet("**Download Only** — SCP the build to the device without flashing. Cancellable."),
                .bullet("**Flash Only** — SSH to the device and run FlashApp on the build already at the destination."),
                .bullet("**Reboot Device** — SSH and run `reboot`."),
                .bullet("**Build Info** — SSHes to the device and reports Image Name, Middleware Version, VIPA/XUMO/PP SKY APP/RDK Browser build strings, OSS/Vendor/Application versions, RDK Type, Branch, Build Time, and AAMP Build Info in a formatted summary."),
                .bullet("**Disable Auto Update** — writes `/opt/persistent/sky/aisettings.overrides.json` to turn off dynamic IUI updates and the startup update check."),
                .bullet("**Edit AAMP Config…** — opens the `/opt/aamp.cfg` editor (see next section)."),
                .bullet("**Clear Log** — empties the progress log.")
            ]),

            HelpSection(title: "Edit AAMP Config", icon: "doc.badge.gearshape", items: [
                .paragraph("""
                Opens a two-pane editor for `/opt/aamp.cfg` on the device. When \
                the sheet opens the current file is fetched automatically.
                """),
                .bullet("**Settings Palette (left)** — your persistent library of config values. Click **＋** to add, drag ≡ to reorder, or use the pencil / trash buttons to edit / delete."),
                .bullet("**Add ⊕** on a palette row appends its value to the config editor on the right."),
                .bullet("**Add all values** (top of palette) appends every value in one go."),
                .bullet("**Load from Device** re-fetches the live file."),
                .bullet("**Save to Device** writes the editor contents atomically to `/opt/aamp.cfg` (via temp file + rename).")
            ]),

            HelpSection(title: "Tips", icon: "lightbulb", items: [
                .bullet("Both the Build Image and Device IP fields have a **clock icon menu** — click it to pick from recent values."),
                .bullet("You can **cancel** an Install or Download mid-flight by pressing the same button again (it turns red and says *Cancel*)."),
                .bullet("The progress bar shows the live SCP transfer percentage. For Flash and Reboot steps a spinner appears instead."),
                .bullet("The progress log is cumulative — output from every action stacks up until you press **Clear Log**.")
            ]),

            HelpSection(title: "Troubleshooting", icon: "wrench.and.screwdriver", items: [
                .bullet("**Device unreachable** — connections time out after 5 seconds. Check that the device is on the same network and that port 10022 is open."),
                .bullet("**FlashApp fails** — make sure the build file made it to the destination folder (try **Download Only** first, then **Flash Only**)."),
                .bullet("**Warnings about known_hosts / post-quantum key exchange** — these are suppressed automatically by using `LogLevel=ERROR`, so they shouldn't clutter the log any more."),
                .bullet("**Nothing happens when I click Install Build** — check that the Build Image path exists and the Device IP is a valid IPv4 address; validation errors are printed to the log.")
            ]),

            HelpSection(title: "Connection Details", icon: "network", items: [
                .bullet("**Protocol**: SSH / SCP"),
                .bullet("**Port**: 10022"),
                .bullet("**User**: root"),
                .bullet("**Connect timeout**: 5 seconds"),
                .bullet("**Host-key checking**: disabled (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`)"),
                .bullet("**SCP mode**: legacy protocol (`-O`) so it works with the device's SCP server.")
            ])
        ]
    }
}

#Preview {
    HelpView()
}
