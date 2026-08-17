import Foundation

/// Version / build information read from a device.
///
/// This is a pure model: it knows how to be *parsed* from the delimited output
/// of the remote shell command, but nothing about how it is displayed.
/// Presentation lives in the view layer (`BuildInfoReport`).
struct BuildInfo: Equatable, Sendable {
    var imageName: String?
    var middleware: String?
    var vipa: String?
    var xumo: String?
    var oss: String?
    var essos: String?
    var vendor: String?
    var application: String?
    var ppSkyApp: String?
    var rdkBrowser: String?
    var rdkType: String?
    var branch: String?
    var buildTime: String?
    var aampBuild: String?
}

// MARK: - Remote command

extension BuildInfo {

    /// Section markers emitted by `remoteCommand` so the response can be split
    /// back into individual fields.
    enum Marker {
        static let image     = "===IMAGE==="
        static let middlware = "===MW==="
        static let vipa      = "===VIPA==="
        static let xumo      = "===XUMO==="
        static let oss       = "===OSS==="
        static let essos     = "===ESSOS==="
        static let vendor    = "===VENDOR==="
        static let app       = "===APP==="
        static let ppSky     = "===PPSKY==="
        static let rdkB      = "===RDKB==="
        static let rdkT      = "===RDKT==="
        static let branch    = "===BRANCH==="
        static let buildTime = "===BUILDTIME==="
        static let aampBuild = "===AAMPB==="
        static let end       = "===END==="

        static let all: [String] = [
            image, middlware, vipa, xumo, oss, essos, vendor, app,
            ppSky, rdkB, rdkT, branch, buildTime, aampBuild, end
        ]
    }

    /// A single shell command that emits every field, delimited by `Marker`s.
    ///
    /// `/version.txt` fields use plain `grep`; log-file fields use
    /// `grep … | tail -n 1` so the newest matching line wins.
    static var remoteCommand: String {
        #"""
        { \
          echo '===IMAGE==='; \
          grep -h 'imagename:' /version.txt 2>/dev/null | tail -n 1; \
          echo '===MW==='; \
          grep -h 'MIDDLEWARE_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===VIPA==='; \
          grep -h 'viper_ipa.*widget version:' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
          echo '===XUMO==='; \
          grep -h "app 'com.xumo.ipa' loaded: version" /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
          echo '===OSS==='; \
          grep -h 'OSS_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===ESSOS==='; \
          grep -h '(essos) version' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
          echo '===VENDOR==='; \
          grep -h 'VENDOR_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===APP==='; \
          grep -h 'APPLICATION_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===PPSKY==='; \
          grep -h 'PP SKY APP version' /opt/logs/sky-messages.log* 2>/dev/null | sort | tail -n 1; \
          echo '===RDKB==='; \
          grep -h 'com.sky.rdkbrowser.*version' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
          echo '===RDKT==='; \
          grep -h 'FW_CLASS=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===BRANCH==='; \
          grep -h 'BRANCH=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===BUILDTIME==='; \
          grep -h 'BUILD_TIME=' /version.txt 2>/dev/null | tail -n 1; \
          echo '===AAMPB==='; \
          grep -h 'AAMP_BUILD_INFO:' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
          echo '===END==='; \
        }
        """#
    }
}

// MARK: - Parsing

extension BuildInfo {

    /// Parses the delimited output produced by `remoteCommand`.
    static func parse(_ raw: String) -> BuildInfo {
        let sections = splitSections(raw)
        var info = BuildInfo()

        // /version.txt style: KEY=VALUE
        info.imageName   = value(after: "imagename:", in: sections[Marker.image], caseInsensitive: true)
        info.middleware  = value(after: "MIDDLEWARE_VERSION=",  in: sections[Marker.middlware])
        info.oss         = value(after: "OSS_VERSION=",         in: sections[Marker.oss])
        info.vendor      = value(after: "VENDOR_VERSION=",      in: sections[Marker.vendor])
        info.application = value(after: "APPLICATION_VERSION=", in: sections[Marker.app])
        info.rdkType     = value(after: "FW_CLASS=",            in: sections[Marker.rdkT])
        info.branch      = value(after: "BRANCH=",              in: sections[Marker.branch])
        info.buildTime   = value(after: "BUILD_TIME=",          in: sections[Marker.buildTime])

        // Log lines: take the text after the keyword (strips the syslog prefix).
        info.aampBuild  = value(after: "AAMP_BUILD_INFO:", in: sections[Marker.aampBuild])
        info.vipa       = value(after: "widget version:",  in: sections[Marker.vipa])
        info.xumo       = value(after: "loaded: version",  in: sections[Marker.xumo])
        info.essos      = value(after: "(essos) version",  in: sections[Marker.essos])
        info.ppSkyApp   = value(after: "version:",         in: sections[Marker.ppSky])
        info.rdkBrowser = value(after: "version",          in: sections[Marker.rdkB])

        return info
    }

    /// Splits raw output into `marker -> body` pairs.
    private static func splitSections(_ raw: String) -> [String: String] {
        var sections: [String: String] = [:]
        var current: String?
        var buffer = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if Marker.all.contains(trimmed) {
                if let key = current {
                    sections[key] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                current = trimmed
                buffer = ""
            } else if current != nil {
                if !buffer.isEmpty { buffer += "\n" }
                buffer += String(line)
            }
        }
        if let key = current {
            sections[key] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sections
    }

    /// Returns the text after the first occurrence of `keyword`, with any
    /// surrounding matched quotes stripped (shell `KEY="value"` style).
    /// Falls back to the whole line when the keyword isn't present.
    private static func value(after keyword: String,
                              in line: String?,
                              caseInsensitive: Bool = false) -> String? {
        guard let line, !line.isEmpty else { return nil }

        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        let candidate: String
        if let range = line.range(of: keyword, options: options) {
            candidate = String(line[range.upperBound...])
        } else {
            candidate = line
        }

        var value = candidate.trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           let first = value.first, let last = value.last,
           first == last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
