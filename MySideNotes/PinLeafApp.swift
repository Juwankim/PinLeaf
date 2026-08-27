//
//  PinLeafApp.swift
//  PinLeaf
//
//

import AppKit
import SwiftUI

@main
struct PinLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The note UI is owned by EdgePanelController; the regular application
        // activation policy still keeps the app icon visible in the Dock.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("PinLeaf 종료") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
