import Foundation

/// View-layer presentation of `BuildInfo`.
///
/// Formatting (column widths, box drawing, "(not found)" placeholders) is a
/// display concern, so it lives here rather than in a view model.
enum BuildInfoReport {

    /// Renders a `BuildInfo` as a monospaced, boxed summary suitable for the
    /// progress log.
    static func format(_ info: BuildInfo) -> String {
        let rows: [(String, String?)] = [
            ("Image Name",          info.imageName),
            ("Middleware Version",  info.middleware),
            ("VIPA Build",          info.vipa),
            ("XUMO Build",          info.xumo),
            ("OSS Version",         info.oss),
            ("Essos Info",          info.essos),
            ("Vendor Version",      info.vendor),
            ("Application Version", info.application),
            ("PP SKY APP version",  info.ppSkyApp),
            ("RDK Browser Version", info.rdkBrowser),
            ("RDK Type",            info.rdkType),
            ("Branch",              info.branch),
            ("Build Time",          info.buildTime),
            ("AAMP Build Info",     info.aampBuild),
        ]

        let labelWidth = rows.map(\.0.count).max() ?? 0
        var out = "\n┌─ Device Build Info ────────────────────────\n"
        for (label, value) in rows {
            let paddedLabel = label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            let display = (value?.isEmpty == false) ? value! : "(not found)"
            out += "│ \(paddedLabel) : \(display)\n"
        }
        out += "└────────────────────────────────────────────\n"
        return out
    }
}
