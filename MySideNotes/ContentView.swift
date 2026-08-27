//
//  ContentView.swift
//  PinLeaf
//
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var panelState: PanelPresentationState
    @ObservedObject var noteStore: NoteStore
    @ObservedObject var floatingPanels: FloatingNotePanelManager
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        NoteWorkspaceView(
            store: noteStore,
            panelState: panelState,
            floatingPanels: floatingPanels,
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.985, green: 0.975, blue: 0.925))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.black.opacity(0.10), lineWidth: 1)
        }
        .padding(.vertical, 8)
        .padding(panelState.edge == .right ? .leading : .trailing, 8)
        .environment(\.colorScheme, .light)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let store = NoteStore()
        ContentView(
            panelState: PanelPresentationState(),
            noteStore: store,
            floatingPanels: FloatingNotePanelManager(store: store),
            onOpenSettings: {},
            onQuit: {}
        )
        .frame(width: 280, height: 640)
    }
}
