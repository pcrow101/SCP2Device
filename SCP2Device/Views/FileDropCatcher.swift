import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// AppKit-backed drop catcher for file URLs — reliable on macOS 26 where
/// SwiftUI's `.onDrop` can be blocked by material/glass wrappers.
struct FileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: (URL) -> Void

    func makeNSView(context: Context) -> DropView {
        let v = DropView()
        v.onEnter = { isTargeted = true }
        v.onExit = { isTargeted = false }
        v.onPerform = { url in
            isTargeted = false
            onDrop(url)
        }
        return v
    }

    func updateNSView(_ nsView: DropView, context: Context) {}

    final class DropView: NSView {
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?
        var onPerform: ((URL) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes([.fileURL])
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onEnter?()
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onExit?()
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pb = sender.draggingPasteboard

            if let urls = pb.readObjects(forClasses: [NSURL.self],
                                         options: [.urlReadingFileURLsOnly: true]) as? [URL],
               let url = urls.first {
                onPerform?(url)
                return true
            }

            if let data = pb.data(forType: .fileURL),
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                onPerform?(url)
                return true
            }

            return false
        }
    }
}
