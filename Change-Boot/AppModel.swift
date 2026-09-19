import AppKit
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
    let configuration: Configuration

    private(set) var detected: [BootSystem] = []
    private(set) var current: BootSystem?
    var busy = false
    var failure: String?

    private var diskObservers: [NSObjectProtocol] = []

    /// `configuration` da się podstawić, żeby sprawdziany nie pisały po ustawieniach
    /// programu.
    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        refresh()
        startWatchingDisks()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in diskObservers { center.removeObserver(observer) }
    }

    /// Wpisy użytkownika zestawione z bieżącym stanem dysków.
    var rows: [SystemRow] {
        configuration.entries.map { entry in
            SystemRow(entry: entry,
                      system: detected.first { $0.volumeUUID == entry.volumeUUID })
        }
    }

    /// Wykryte systemy, których nie ma jeszcze w konfiguracji.
    ///
    /// Bieżący system jest z tej listy wyłączony zawsze: stoi osobno jako „ten system"
    /// i wchodzi do konfiguracji sam. Bez tego warunku pokazywał się dwa razy — raz
    /// u góry, raz z przyciskiem „Dodaj".
    var unconfigured: [BootSystem] {
        detected.filter { !configuration.contains($0) && !isCurrent($0) }
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
        // System, z którego maszyna pracuje, jest na liście zawsze i bez pytania.
        if let current { configuration.add(current) }
    }

    /// Nasłuch podłączania i odłączania dysków.
    ///
    /// Powiadomienia idą przez **własne** centrum `NSWorkspace`, nie przez
    /// `NotificationCenter.default` — wysłane tam nigdy by nie dotarły, a lista
    /// nie odświeżałaby się po wpięciu dysku.
    func startWatchingDisks() {
        guard diskObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            diskObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                })
        }
    }

    // MARK: - Działania

    func switchTo(_ system: BootSystem, cleanStart: Bool) {
        guard !busy else { return }
        busy = true
        failure = nil
        do {
            // Czysty start stoi na dwóch rzeczach naraz: preferencji ustawionej tutaj
            // i na tym, że `restart()` idzie z parametrem `state saving preference`.
            // Samo ustawienie preferencji nic nie daje — zmierzone 2026-09-19.
            let preferencjaPrzyjeta = BootActions.setWindowRestore(!cleanStart)

            // Dysk startowy ustawiamy PRZED zamykaniem programów: gdyby bless się nie
            // udał albo użytkownik cofnął hasło, nikt nie traci otwartej pracy.
            try BootActions.setStartupDisk(to: system)

            // Droga awaryjna: preferencja się nie zapisała, więc zamykamy programy
            // ręcznie. Zamknięty program nie ma jak wrócić, cokolwiek loginwindow
            // sobie zapisze.
            if cleanStart && !preferencjaPrzyjeta {
                let oporne = BootActions.closeUserApps()
                if !oporne.isEmpty {
                    failure = String(localized: "These apps did not close: \(oporne.joined(separator: ", ")).\n\nThey probably have unsaved work. Deal with them and switch again — the startup disk is already set.")
                    busy = false
                    return
                }
            }

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

/// Decyduje, czy zamknięcie okna kończy program.
///
/// SwiftUI domyślnie kończy aplikację po zamknięciu ostatniego okna, także wtedy,
/// gdy `MenuBarExtra` jest widoczne — czerwony przycisk ubijał wtedy program mimo
/// ikony w pasku. Z ikoną w pasku program ma zostać; bez niej musi się zakończyć,
/// bo inaczej zostałby bez okna i bez ikony, czyli nie do odzyskania.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Configuration.Key.menuBar)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for nazwa in [NSWindow.willCloseNotification, NSWindow.didBecomeMainNotification] {
            NotificationCenter.default.addObserver(forName: nazwa, object: nil, queue: .main) { _ in
                // `willClose` leci ZANIM okno zniknie z `NSApp.windows`, więc licząc
                // okna w tej samej turze naliczylibyśmy je jeszcze raz.
                DispatchQueue.main.async { AppDelegate.aktualizujObecnoscWDocku() }
            }
        }
        AppDelegate.aktualizujObecnoscWDocku()
    }

    /// Zdejmuje program z Docka albo go tam przywraca.
    ///
    /// Trzy warunki naraz, bo każdy inaczej kończy się programem nie do odzyskania:
    /// ustawienie włączone, ikona w pasku menu obecna (inaczej nie ma jak wrócić)
    /// i żadnego otwartego okna (z otwartym oknem `.accessory` zabrałoby menu górne).
    ///
    /// 🔴 Do 0.1.16 tego **w ogóle nie było**. Notatka projektu twierdziła, że
    /// `setActivationPolicy(.accessory)` wszedł w 0.1.7 — `git log -S` nie pokazuje
    /// ani jednego commita z tym wywołaniem. Ikona w Docku nigdy nie znikała.
    static func aktualizujObecnoscWDocku() {
        let chowamy = UserDefaults.standard.bool(forKey: Configuration.Key.hideDock)
        let pasek = UserDefaults.standard.bool(forKey: Configuration.Key.menuBar)
        let celPolityki: NSApplication.ActivationPolicy =
            (chowamy && pasek && !maOtwarteOkno()) ? .accessory : .regular
        guard NSApp.activationPolicy() != celPolityki else { return }
        NSApp.setActivationPolicy(celPolityki)
    }

    /// Czy program ma otwarte zwykłe okno.
    ///
    /// Sam `NSApp.windows` nie wystarcza: siedzi tam okno pozycji paska menu,
    /// a także okna pomocnicze bez ramki. Liczą się tylko okna z paskiem tytułu.
    private static func maOtwarteOkno() -> Bool {
        NSApp.windows.contains { okno in
            okno.isVisible && okno.styleMask.contains(.titled) && !(okno is NSPanel)
        }
    }

    /// Wywoływane, zanim program otworzy okno z menu paska — bez powrotu do
    /// `.regular` okno programu bez ikony w Docku nie wychodzi na wierzch.
    static func przygotujNaOkno() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }
}

