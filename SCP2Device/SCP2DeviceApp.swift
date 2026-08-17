//
//  SCP2DeviceApp.swift
//  SCP2Device
//
//  Created by paucrow on 19/03/2026.
//

import SwiftUI

@main
struct SCP2DeviceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 700, height: 620)
        .windowStyle(.automatic)
        .commands {
            HelpMenuCommands()
        }

        Window("SCP2Device Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 720, height: 700)
    }
}

/// Replaces the standard Help menu with an in-app help command that opens
/// the dedicated Help window.
private struct HelpMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("SCP2Device Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: [.command])
        }
    }
}
