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
            MenuBarLabel(count: store.badgeCount, notesFull: store.isInboxFull)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let count: Int
    let notesFull: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "memorychip.fill" : "memorychip")
            if count > 0 {
                Text("\(count)")
            }
            if notesFull {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
            }
        }
    }
}