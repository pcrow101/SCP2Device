import Foundation

/// A user-creatable config value. Double-clicking one in the palette appends
/// its `value` to the AAMP config being edited.
struct ConfigSnippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var value: String   // the config line inserted into the config

    /// Seed examples shown the first time the palette is opened.
    static let defaults: [ConfigSnippet] = [
        ConfigSnippet(value: "info=true"),
        ConfigSnippet(value: "progress-interval=1"),
        ConfigSnippet(value: "default-bitrate=2500000")
    ]
}
