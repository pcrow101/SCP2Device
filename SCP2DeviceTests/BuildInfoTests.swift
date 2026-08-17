import Testing
import Foundation
@testable import SCP2Device

// MARK: - BuildInfo: comprehensive field parsing (item 1)
//
// The existing "BuildInfo Parsing" suite in WorkflowTests.swift covers a few
// spot cases. This suite exhaustively verifies every one of the 14 fields, the
// keyword-fallback behaviour, and quote handling.

@Suite("BuildInfo Field Parsing")
struct BuildInfoFieldParsingTests {

    /// A realistic full payload exercising every field, mixing version.txt
    /// `KEY=VALUE` lines with syslog-prefixed log lines.
    private static let fullPayload = """
    ===IMAGE===
    imagename: SKXI11ADS_TEST_20260810
    ===MW===
    MIDDLEWARE_VERSION="1.2.3"
    ===VIPA===
    2026-08-10 09:00:00.123 xione viper_ipa: widget version: 5.6.7
    ===XUMO===
    2026-08-10 09:01:00.000 xione app 'com.xumo.ipa' loaded: version 9.8.7
    ===OSS===
    OSS_VERSION="4.5.6"
    ===ESSOS===
    2026-08-10 09:02:00 xione (essos) version 1.19.0
    ===VENDOR===
    VENDOR_VERSION="SYNA_7.11"
    ===APP===
    APPLICATION_VERSION="2.0.1"
    ===PPSKY===
    2026-08-10 09:03:00 xione PP SKY APP version: 3.14.15
    ===RDKB===
    2026-08-10 09:04:00 xione com.sky.rdkbrowser2 version 0.55.0
    ===RDKT===
    FW_CLASS="LLAMA"
    ===BRANCH===
    BRANCH="develop"
    ===BUILDTIME===
    BUILD_TIME="Mon Aug 10 09:00:00 UTC 2026"
    ===AAMPB===
    2026-08-10 09:05:00 xione AAMP_BUILD_INFO: aamp-6.6.6-release
    ===END===
    """

    @Test("All 14 fields parse from a full payload")
    func allFieldsParse() {
        let info = BuildInfo.parse(Self.fullPayload)

        #expect(info.imageName   == "SKXI11ADS_TEST_20260810")
        #expect(info.middleware  == "1.2.3")
        #expect(info.vipa        == "5.6.7")
        #expect(info.xumo        == "9.8.7")
        #expect(info.oss         == "4.5.6")
        #expect(info.essos       == "1.19.0")
        #expect(info.vendor      == "SYNA_7.11")
        #expect(info.application == "2.0.1")
        #expect(info.ppSkyApp    == "3.14.15")
        #expect(info.rdkBrowser  == "0.55.0")
        #expect(info.rdkType     == "LLAMA")
        #expect(info.branch      == "develop")
        #expect(info.buildTime   == "Mon Aug 10 09:00:00 UTC 2026")
        #expect(info.aampBuild   == "aamp-6.6.6-release")
    }

    @Test("Completely empty output yields an all-nil BuildInfo")
    func emptyOutput() {
        let info = BuildInfo.parse("")
        #expect(info == BuildInfo())
    }

    @Test("Image name matching is case-insensitive")
    func imageNameCaseInsensitive() {
        let raw = "===IMAGE===\nIMAGENAME: UPPER_CASE_BUILD\n===END==="
        #expect(BuildInfo.parse(raw).imageName == "UPPER_CASE_BUILD")
    }

    @Test("Single quotes are stripped as well as double quotes")
    func stripsSingleQuotes() {
        let raw = "===BRANCH===\nBRANCH='release/1.0'\n===END==="
        #expect(BuildInfo.parse(raw).branch == "release/1.0")
    }

    @Test("Mismatched surrounding quotes are left intact")
    func mismatchedQuotesKept() {
        let raw = "===BRANCH===\nBRANCH=\"develop'\n===END==="
        #expect(BuildInfo.parse(raw).branch == "\"develop'")
    }

    @Test("Internal spaces in a quoted value are preserved")
    func preservesInternalSpaces() {
        let raw = "===BUILDTIME===\nBUILD_TIME=\"Fri Aug  4 12:34:56 2026\"\n===END==="
        #expect(BuildInfo.parse(raw).buildTime == "Fri Aug  4 12:34:56 2026")
    }

    @Test("A section without its keyword falls back to the whole line")
    func fallbackToWholeLine() {
        // grep normally guarantees the keyword is present, but if it isn't the
        // parser should still surface whatever text was returned.
        let raw = "===OSS===\nunexpected raw text\n===END==="
        #expect(BuildInfo.parse(raw).oss == "unexpected raw text")
    }

    @Test("An empty section body parses as nil, not empty string")
    func emptySectionIsNil() {
        let raw = "===OSS===\n===VENDOR===\nVENDOR_VERSION=1.0\n===END==="
        let info = BuildInfo.parse(raw)
        #expect(info.oss == nil)
        #expect(info.vendor == "1.0")
    }

    @Test("Unknown markers between known ones don't corrupt fields")
    func unknownMarkersIgnored() {
        // "===BOGUS===" is not in Marker.all, so it becomes body text of the
        // preceding section rather than a delimiter.
        let raw = """
        ===BRANCH===
        BRANCH=develop
        ===BOGUS===
        ===BUILDTIME===
        BUILD_TIME=now
        ===END===
        """
        let info = BuildInfo.parse(raw)
        #expect(info.buildTime == "now")
        // branch body now contains the bogus marker line, but the keyword is on
        // the first line so extraction still yields everything after "BRANCH=".
        #expect(info.branch?.hasPrefix("develop") == true)
    }

    @Test("The last field before END is captured (final-buffer flush)")
    func finalSectionFlushed() {
        // Regression: an earlier version of splitSections never flushed the
        // final section if END was absent.
        let raw = "===AAMPB===\nAAMP_BUILD_INFO: tail-value"
        #expect(BuildInfo.parse(raw).aampBuild == "tail-value")
    }
}
