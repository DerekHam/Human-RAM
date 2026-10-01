import SwiftUI
import AppKit
import HumanRAMCore

@main
struct HumanRAMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ItemStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    /// The label hosts its own status-item view, so it must observe the store
    /// itself. Passing a precomputed value from the App body leaves the number
    /// stale when items change.
    @ObservedObject var store: ItemStore

    var body: some View {
        let loaded = store.loaded.count
        HStack(spacing: 3) {
            Image(systemName: loaded > 0 ? "memorychip.fill" : "memorychip")
            if loaded > 0 {
                Text("\(loaded)")
            }
            if !store.dueNow.isEmpty {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
            }
            if store.isInboxFull {
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
            }
        }
    }
}