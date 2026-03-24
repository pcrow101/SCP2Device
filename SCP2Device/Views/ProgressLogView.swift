import SwiftUI

/// A scrollable, read-only text area that displays progress log output.
struct ProgressLogView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "Ready." : text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
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
}
