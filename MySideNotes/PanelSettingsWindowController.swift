//
//  PanelSettingsWindowController.swift
//  PinLeaf
//

import AppKit
import SwiftUI

@MainActor
final class PanelSettingsWindowController: NSWindowController, NSWindowDelegate {
    init(panelState: PanelPresentationState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PinLeaf – Sticky Notes 설정"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .utilityWindow
        window.contentView = NSHostingView(
            rootView: PanelSettingsView(panelState: panelState)
                .environment(\.colorScheme, .light)
        )
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func closePermanently() {
        window?.delegate = nil
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
