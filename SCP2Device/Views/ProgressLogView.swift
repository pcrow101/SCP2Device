import SwiftUI

/// A scrollable, read-only text area that displays progress log output.
///
/// Each line is colour-coded by its content so successes, failures and warnings
/// stand out at a glance. Colouring is purely presentational — the underlying
/// log remains a plain `String` owned by `DeviceSession`.
struct ProgressLogView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if text.isEmpty {
                        Text("Ready.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(styledLog(text))
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
                .id("logBottom")
            }
            .onChange(of: text) {
                withAnimation {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Styling

    /// Builds a coloured `AttributedString` from the raw log, styling each line
    /// according to its content. Rendering it as a single `Text` keeps
    /// contiguous text selection across the whole log.
    private func styledLog(_ raw: String) -> AttributedString {
        var result = AttributedString()
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            var piece = AttributedString(String(line))
            let style = LogLineStyle.classify(String(line))
            piece.foregroundColor = style.color
            if style.bold {
                piece.font = .system(.body, design: .monospaced).bold()
            }
            result += piece

            // Re-insert the newline that `split` consumed (except after the last).
            if index < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }
}

/// Classifies a single log line and maps it to a colour.
///
/// Most app-generated lines carry a leading status glyph (✔ ✖ ⚠ ▶ ━ →). Raw
/// tool output (stderr from `ssh`/`scp`) carries no glyph, so failure lines such
/// as connection timeouts are additionally detected by their text content —
/// otherwise a timeout would render in plain black rather than red.
enum LogLineStyle: Equatable {
    case success       // ✔
    case failure       // ✖  or raw ssh/scp error output
    case warning       // ⚠  or "warning" text
    case sectionHeader // ━━━ … ━━━
    case command       // ▶ (echoed scp/ssh command)
    case info          // → device-type notes etc.
    case report        // ┌ │ └ build-info table
    case plain

    var color: Color {
        switch self {
        case .success:       return .green
        case .failure:       return .red
        case .warning:       return .orange
        case .sectionHeader: return .accentColor
        case .command:       return .blue
        case .info:          return .secondary
        case .report:        return .teal
        case .plain:         return .primary
        }
    }

    var bold: Bool {
        switch self {
        case .success, .failure, .warning, .sectionHeader: return true
        default: return false
        }
    }

    /// Phrases that mark a line as a failure even without a leading ✖ glyph.
    /// These are the kinds of messages ssh/scp print to stderr.
    private static let failurePhrases = [
        "timed out", "timeout",
        "connection refused", "connection reset", "connection closed",
        "lost connection",
        "no route to host", "network is unreachable", "host is down",
        "permission denied", "operation not permitted",
        "could not resolve", "name or service not known",
        "no such file or directory",
        "authentication failed",
        "failed"
    ]

    static func classify(_ line: String) -> LogLineStyle {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return .plain }

        // 1. App-generated lines carry an explicit status glyph.
        switch first {
        case "✔": return .success
        case "✖": return .failure
        case "⚠": return .warning
        case "━": return .sectionHeader
        case "▶": return .command
        case "→": return .info
        case "┌", "│", "└", "├": return .report
        default: break
        }

        // 2. Raw tool output (ssh/scp stderr) carries no glyph. Detect failures
        //    by prefix and by well-known error phrases so e.g. a connection
        //    timeout shows in red rather than plain black.
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ssh:") || lower.hasPrefix("scp:") {
            return .failure
        }
        if lower.contains("warning") {
            return .warning
        }
        if failurePhrases.contains(where: lower.contains) {
            return .failure
        }
        return .plain
    }
}
