import AppKit
import SwiftUI

@main
struct ChangeBootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Change-Boot", id: "main") {
            RootView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 420)

        MenuBarExtra(isInserted: Binding(
                        get: { model.configuration.showsMenuBarIcon },
                        set: { model.configuration.showsMenuBarIcon = $0 })) {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarIcon()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.configuration.setupCompleted {
            ContentView()
        } else {
            SetupView()
        }
    }
}
