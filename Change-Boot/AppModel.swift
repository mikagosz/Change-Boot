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
    /// UUID woluminu, na którym trwa właśnie czynność — wiersz listy rysuje wtedy
    /// w miejscu ikony dysku śmigło.
    ///
    /// Osobne pole, a nie samo `busy`: śmigło ma stać **przy dysku, którego
    /// dotyczy**, a nie w stopce okna obok numeru wersji. Polecenie [U] 2026-09-19:
    /// *„jak mamy ten dysk koloru zielonego, to on wtedy w momencie wypinania znika
    /// i włącza się to śmigło wirujące"*.
    private(set) var busyVolumeUUID: String?
    /// Trwa odczytywanie dysków. Osobne od `busy`: skanowanie nie jest czynnością
    /// użytkownika i nie ma wyłączać przycisków, ma tylko pokazać, że lista żyje.
    private(set) var skanowanie = false
    var failure: String?

    private var diskObservers: [NSObjectProtocol] = []
    /// Dławik powiadomień o dyskach — patrz `odswiezZeZwloka`.
    private var dlawik: DispatchWorkItem?
    /// Zgłoszenie odświeżenia, które przyszło w trakcie poprzedniego.
    private var odswiezycPonownie = false
    /// Domknięcia czekające na koniec odświeżania.
    ///
    /// 🔴 Lista, nie jedno pole, i nie wolno ich gubić. `eject` oddaje tędy
    /// zgaszenie śmigła i zdjęcie blokady `busy` — domknięcie zgubione przy
    /// zbiegu z dławionym odświeżeniem zostawiłoby program zablokowany na stałe.
    private var poOdswiezeniu: [() -> Void] = []

    /// `configuration` da się podstawić, żeby sprawdziany nie pisały po ustawieniach
    /// programu.
    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        refresh()
        startWatchingDisks()
    }

    deinit {
        dlawik?.cancel()
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

    /// Odczytuje dyski **w tle** i dopiero wynik wstawia na wątek główny.
    ///
    /// 🔴 Do 0.2.4 leciało to wprost na wątku głównym i kosztowało **1 308 ms** —
    /// zmierzone 2026-09-19. Okno zamierało przy każdym wpięciu i wypięciu
    /// dowolnego dysku, także takiego, który z programem nie ma nic wspólnego.
    /// Zjadało też śmigło z 0.2.3: wysuwanie chodziło już w tle, ale powiadomienia
    /// o odmontowaniu wracały tutaj i zatrzymywały animację (P1-02 z audytu).
    ///
    /// Zgłoszenie, które przyjdzie w trakcie trwającego odczytu, nie ustawia się
    /// w kolejce po raz drugi — zapamiętuje się jako jedno „jeszcze raz na koniec".
    func refresh(potem: (() -> Void)? = nil) {
        if let potem { poOdswiezeniu.append(potem) }
        guard !skanowanie else {
            odswiezycPonownie = true
            return
        }
        skanowanie = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let znalezione = SystemScanner.scan()
            let biezacy = SystemScanner.current()

            DispatchQueue.main.async {
                guard let self else { return }
                self.detected = znalezione
                self.current = biezacy
                // Dysk mógł zostać przemianowany — konfiguracja nadąża sama, bo trzyma UUID.
                for system in znalezione { self.configuration.refreshName(for: system) }
                // System, z którego maszyna pracuje, jest na liście zawsze i bez pytania.
                if let biezacy { self.configuration.add(biezacy) }
                self.skanowanie = false
                let doWykonania = self.poOdswiezeniu
                self.poOdswiezeniu.removeAll()
                for blok in doWykonania { blok() }
                if self.odswiezycPonownie {
                    self.odswiezycPonownie = false
                    self.refresh()
                }
            }
        }
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
                    self?.odswiezZeZwloka()
                })
        }
    }

    /// Odświeżenie po chwili ciszy, nie po każdym powiadomieniu.
    ///
    /// Wysunięcie jednego nośnika wysyła **po jednym powiadomieniu na wolumin**,
    /// a kontener APFS instalacji macOS niesie ich kilka — system, dane, Preboot,
    /// Recovery. Bez dławienia jedno wyciągnięcie dysku znaczyło kilka pełnych
    /// przejazdów po `diskutil` pod rząd.
    private func odswiezZeZwloka() {
        dlawik?.cancel()
        let zadanie = DispatchWorkItem { [weak self] in self?.refresh() }
        dlawik = zadanie
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: zadanie)
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
                    EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: current, na: system,
                                    czystyStart: cleanStart, zrodlo: .okno,
                                    szczegol: "nie zamknęły się: \(oporne.joined(separator: ", "))")
                    busy = false
                    return
                }
            }

            EventLog.zapisz(.przelaczenie, skutek: .udane, z: current, na: system,
                            czystyStart: cleanStart, zrodlo: .okno)

            // Wpis logowania zakładamy na TYM systemie, tuż przed jego opuszczeniem —
            // odpali się, gdy tu wrócimy. Nie rzuca: przełączenie idzie dalej nawet
            // wtedy, gdy wpisu nie dało się założyć.
            if configuration.launchAfterSwitch { LoginItem.uzbrojNaPowrot() }

            try BootActions.restart()
        } catch BootError.cancelled {
            // Użytkownik zamknął okno hasła — nic się nie stało.
            EventLog.zapisz(.przelaczenie, skutek: .anulowane, z: current, na: system,
                            czystyStart: cleanStart, zrodlo: .okno)
        } catch {
            failure = error.localizedDescription
            EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: current, na: system,
                            czystyStart: cleanStart, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
        busy = false
    }

    /// Wysuwa dysk **w tle**, nie na wątku okna.
    ///
    /// 🔴 To nie jest ozdobnik. Do 0.2.2 `diskutil eject` blokował wątek główny, więc
    /// śmigło nie miało kiedy narysować ani jednej klatki — animacja w SwiftUI chodzi
    /// na tym samym wątku, który właśnie czeka na `waitUntilExit()`. Wskaźnik pracy
    /// dorysowany bez przeniesienia roboty w tło stałby nieruchomo.
    func eject(_ system: BootSystem) {
        guard !busy else { return }
        busy = true
        busyVolumeUUID = system.volumeUUID
        failure = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var blad: Error?
            do { try BootActions.eject(system) } catch { blad = error }

            DispatchQueue.main.async {
                guard let self else { return }
                if let blad {
                    self.failure = blad.localizedDescription
                    EventLog.zapisz(.wysuniecie, skutek: .nieudane, na: system, zrodlo: .okno,
                                    szczegol: blad.localizedDescription)
                } else {
                    EventLog.zapisz(.wysuniecie, skutek: .udane, na: system, zrodlo: .okno)
                }
                // Śmigło gaśnie dopiero, gdy lista zna już nowy stan — inaczej
                // wiersz wraca na moment do wyglądu „dysk dostępny" i dopiero
                // potem znika.
                self.refresh {
                    self.busyVolumeUUID = nil
                    self.busy = false
                }
            }
        }
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
        !AppBundle.defaults.bool(forKey: Configuration.Key.menuBar)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wpis logowania założony przed przełączeniem zrobił swoje — program
        // właśnie wstał. Zdejmujemy go, żeby nie został na zawsze.
        LoginItem.rozbrojPoStarcie()

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
        let chowamy = AppBundle.defaults.bool(forKey: Configuration.Key.hideDock)
        let pasek = AppBundle.defaults.bool(forKey: Configuration.Key.menuBar)
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

    /// Panel „Biurko i Dock" w Ustawieniach systemowych.
    ///
    /// Stoi tutaj, bo prowadzi do przełącznika „Pokazuj sugerowane i ostatnie
    /// aplikacje w Docku" — jedynej rzeczy, która potrafi wstawić program
    /// z powrotem do Docka mimo ustawienia po naszej stronie. Identyfikator
    /// panelu zmierzony: `CFBundleIdentifier` z `DesktopSettings.appex`.
    static func otworzUstawieniaDocka() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Wywoływane, zanim program otworzy okno z menu paska — bez powrotu do
    /// `.regular` okno programu bez ikony w Docku nie wychodzi na wierzch.
    static func przygotujNaOkno() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }
}

