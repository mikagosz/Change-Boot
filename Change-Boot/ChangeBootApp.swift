import SwiftUI
import Observation

/// Wiersz listy: zapamiętany wpis zestawiony z tym, co widać teraz na dyskach.
struct SystemRow: Identifiable {
    let entry: Configuration.Entry
    let system: BootSystem?

    var id: String { entry.volumeUUID }
    var name: String { system?.name ?? entry.lastKnownName }
    var isAvailable: Bool { system != nil }
}

@Observable
final class AppModel {
    let configuration = Configuration()

    private(set) var detected: [BootSystem] = []
    private(set) var current: BootSystem?
    var busy = false
    var failure: String?

    init() { refresh() }

    /// Wpisy użytkownika zestawione z bieżącym stanem dysków.
    var rows: [SystemRow] {
        configuration.entries.map { entry in
            SystemRow(entry: entry,
                      system: detected.first { $0.volumeUUID == entry.volumeUUID })
        }
    }

    /// Wykryte systemy, których nie ma jeszcze w konfiguracji.
    var unconfigured: [BootSystem] {
        detected.filter { !configuration.contains($0) }
    }

    func isCurrent(_ system: BootSystem?) -> Bool {
        guard let system, let current else { return false }
        return system.volumeUUID == current.volumeUUID
    }

    func refresh() {
        detected = SystemScanner.scan()
        current = SystemScanner.current()
        // Dysk mógł zostać przemianowany — konfiguracja nadąża sama, bo trzyma UUID.
        for system in detected { configuration.refreshName(for: system) }
    }

    // MARK: - Działania

    func switchTo(_ system: BootSystem, cleanStart: Bool) {
        guard !busy else { return }
        busy = true
        failure = nil
        do {
            BootActions.setWindowRestore(!cleanStart)
            try BootActions.setStartupDisk(to: system)
            try BootActions.restart()
        } catch BootError.cancelled {
            // Użytkownik zamknął okno hasła — nic się nie stało.
        } catch {
            failure = error.localizedDescription
        }
        busy = false
    }

    func eject(_ system: BootSystem) {
        guard !busy else { return }
        busy = true
        failure = nil
        do {
            try BootActions.eject(system)
            refresh()
        } catch {
            failure = error.localizedDescription
        }
        busy = false
    }
}

@main
struct ChangeBootApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Change-Boot", id: "main") {
            RootView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 420)

        MenuBarExtra("Change-Boot", systemImage: "internaldrive",
                     isInserted: Binding(
                        get: { model.configuration.showsMenuBarIcon },
                        set: { model.configuration.showsMenuBarIcon = $0 })) {
            MenuBarContent()
                .environment(model)
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
