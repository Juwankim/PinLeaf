//
//  AppDelegate.swift
//  PinLeaf
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var edgePanelController: EdgePanelController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let activationPolicy: NSApplication.ActivationPolicy =
            PanelPresentationState.savedShowsDockIcon() ? .regular : .accessory
        NSApp.setActivationPolicy(activationPolicy)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelConfiguration = EdgePanelConfiguration(
            edge: .left,
            collapsedPeekWidth: 4
        )
        let controller = EdgePanelController(configuration: panelConfiguration)
        controller.start()
        edgePanelController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        edgePanelController?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        edgePanelController?.showAndActivate()
        return true
    }
}
