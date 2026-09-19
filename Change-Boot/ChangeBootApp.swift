import AppKit
import SwiftUI

/// Bez `@main` — punkt wejścia siedzi w `main.swift`, bo ta sama binarka bywa
/// uruchamiana przez launchd jako demon roota.
struct ChangeBootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Change-Boot", id: "main") {
            RootView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 444)
        .commands {
            // Zaraz za „O programie Change-Boot", czyli tam, gdzie macOS trzyma
            // rzeczy dotyczące samego programu.
            CommandGroup(after: .appInfo) {
                LanguageMenu()
                Divider()
            }
        }

        MenuBarExtra(isInserted: Binding(
                        get: { model.configuration.showsMenuBarIcon },
                        set: { model.configuration.showsMenuBarIcon = $0 })) {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarIconView(monochromatyczna: model.configuration.monochromeMenuBarIcon)
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
