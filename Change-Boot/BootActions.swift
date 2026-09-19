import AppKit
import Foundation

enum BootError: LocalizedError {
    case volumeUnavailable(String)
    case blessFailed(String)
    case verificationFailed(expected: String, actual: String)
    case ejectFailed(disk: String, message: String, blockers: [String])
    case refusedInternalDisk(String)
    case refusedRunningSystem(String)
    /// Wolumin spoza listy dozwolonej profilem konfiguracyjnym.
    case refusedByPolicy(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .volumeUnavailable(let name):
            return String(localized: "Volume “\(name)” is not available. Connect the disk and try again.")
        case .blessFailed(let message):
            return String(localized: "Could not set the startup disk.\n\n\(message)")
        case .verificationFailed(let expected, let actual):
            return String(localized: "bless reported success, but the startup disk is still /dev/\(actual) instead of /dev/\(expected). Restart was stopped — the Mac would have booted the wrong system.")
        case .ejectFailed(let disk, let message, let blockers):
            let who = blockers.isEmpty
                ? ""
                : String(localized: "\n\nHeld by: \(blockers.joined(separator: ", "))")
            return String(localized: "Could not eject \(disk).\n\n\(message)\(who)\n\nDo NOT unplug the disk — it is still mounted.")
        case .refusedInternalDisk(let name):
            return String(localized: "“\(name)” is on an internal disk and cannot be ejected.")
        case .refusedRunningSystem(let name):
            return String(localized: "“\(name)” is the system you are running from. Switch to another system first.")
        case .refusedByPolicy(let name):
            let kto = Polityka.organizacja ?? String(localized: "your organization")
            return String(localized: "“\(name)” is not on the list of systems allowed by \(kto). Nothing was changed.")
        case .cancelled:
            return nil
        }
    }
}

enum BootActions {

    // MARK: - Dysk startowy

    /// Ustawia dysk startowy **na stałe** i sprawdza, czy firmware faktycznie go przyjął.
    ///
    /// Świadomie bez `--nextonly`: ta flaga zmienia wybór tylko na jeden start,
    /// więc powrót na poprzedni system nie zostaje zapisany i maszyna przy
    /// kolejnym rozruchu szuka dysku, którego nie ma (`missing-boot-media`).
    static func setStartupDisk(to system: BootSystem) throws {
        // 🔴 Polityka przed wszystkim innym, także przed sprawdzeniem, czy dysk
        // jest podpięty: odmowa ma brzmieć tak samo niezależnie od tego, czy
        // wolumin akurat stoi w maszynie. Inaczej komunikat błędu mówiłby
        // administratorowi, które zakazane dyski użytkownik ma pod ręką.
        guard Polityka.czyWolnoStartowac(system) else {
            throw BootError.refusedByPolicy(system.name)
        }
        guard FileManager.default.fileExists(atPath: system.mountPoint) else {
            throw BootError.volumeUnavailable(system.name)
        }

        // Profil może zażądać hasła przy każdym przełączeniu — wtedy pomijamy
        // pomocnika, choćby stał gotowy. To jest cała treść tej reguły:
        // przełączenie ma kosztować świadomy gest, a nie jedno kliknięcie.
        if Polityka.wymagajHasla {
            let quoted = system.mountPoint.replacingOccurrences(of: "'", with: "'\\''")
            _ = try PrivilegedShell.run("/usr/sbin/bless --mount '\(quoted)' --setBoot 2>&1")
            try sprawdzFirmware(system)
            return
        }

        // Najpierw pomocnik: zarejestrowany demon robi to bez pytania o hasło.
        // Dopiero gdy go nie ma albo milczy, zostaje systemowe okno hasła.
        do {
            try HelperClient.setStartupDisk(mountPoint: system.mountPoint)
        } catch let HelperClient.Failure.bless(code, output) {
            // Pomocnik odpowiedział, ale `bless` odmówił — to nie jest powód, żeby
            // pytać o hasło i próbować drugi raz tego samego.
            throw BootError.blessFailed("bless (\(code))\n\(output)")
        } catch {
            let quoted = system.mountPoint.replacingOccurrences(of: "'", with: "'\\''")
            _ = try PrivilegedShell.run("/usr/sbin/bless --mount '\(quoted)' --setBoot 2>&1")
        }

        try sprawdzFirmware(system)
    }

    /// Sukces `bless`-a to za mało: sprawdzamy, na co naprawdę wskazuje firmware.
    /// Wydzielone, bo obie drogi — przez pomocnika i przez okno hasła — muszą
    /// kończyć się tym samym sprawdzeniem, a nie każda własną kopią.
    private static func sprawdzFirmware(_ system: BootSystem) throws {
        let actual = currentStartupDevice()
        let expected = system.deviceIdentifier
        if let actual, actual != expected {
            throw BootError.verificationFailed(expected: expected, actual: actual)
        }
    }

    /// Urządzenie, z którego maszyna wystartuje (`disk5s2`), albo `nil`, gdy nie da się ustalić.
    static func currentStartupDevice() -> String? {
        guard let data = DiskUtility.run("/usr/sbin/bless", ["--info", "--getBoot"]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/dev/") else { return nil }
        return String(trimmed.dropFirst("/dev/".count))
    }

    // MARK: - Okna po restarcie

    /// Włącza albo wyłącza przywracanie programów i okien po ponownym starcie.
    ///
    /// To ta sama preferencja, którą przestawia checkbox „Otwórz ponownie okna
    /// przy następnym logowaniu" w systemowym oknie restartu — jedyne ustawienie
    /// poza NVRAM-em, jakie ten program rusza.
    ///
    /// 🔴 Sama ta preferencja **nic nie znaczy**, dopóki restart nie idzie z
    /// parametrem `state saving preference` — patrz `restart()`. Do 0.1.7 program
    /// stawiał ją na `0` i restartował poleceniem, które stan zapisuje zawsze.
    ///
    /// Zwraca to, co po zapisie faktycznie siedzi w preferencjach: `cfprefsd`
    /// potrafi zapis przyjąć i nie donieść o porażce, a orzekanie o czystym starcie
    /// bez odczytu zwrotnego to zgadywanie.
    @discardableResult
    static func setWindowRestore(_ enabled: Bool) -> Bool {
        CFPreferencesSetValue("TALLogoutSavesState" as CFString,
                              enabled as CFBoolean,
                              "com.apple.loginwindow" as CFString,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize("com.apple.loginwindow" as CFString)

        let zapisane = CFPreferencesCopyValue("TALLogoutSavesState" as CFString,
                                              "com.apple.loginwindow" as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? Bool
        return zapisane == enabled
    }

    // MARK: - Zamykanie programów

    /// Zamyka programy użytkownika i zwraca nazwy tych, które się nie poddały.
    ///
    /// **Droga awaryjna, nie główna.** Czysty start robi para: `TALLogoutSavesState`
    /// na `0` plus restart z `state saving preference`. Tędy idziemy dopiero wtedy,
    /// gdy odczyt zwrotny preferencji pokaże, że zapis się nie przyjął — wtedy
    /// zostaje twardsze narzędzie: program zamknięty **przed** restartem nie ma jak
    /// wrócić, bo loginwindow wznawia to, co działało w chwili wylogowania.
    ///
    /// Cena jest realna i dlatego to nie jest domyślna ścieżka: `terminate()` ubija
    /// sesje otwartych programów (w tym Claude) zamiast pozwolić im wyjść normalną
    /// drogą wylogowania.
    ///
    /// Finder zostaje — jego „zamknięcie" to i tak ponowne uruchomienie, a bez niego
    /// pulpit znika na chwilę bez żadnego zysku.
    static func closeUserApps(waitingUpTo limit: TimeInterval = 6) -> [String] {
        let wlasny = NSRunningApplication.current.processIdentifier

        func doZamkniecia() -> [NSRunningApplication] {
            NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != wlasny
                    && $0.bundleIdentifier != "com.apple.finder"
                    && !$0.isTerminated
            }
        }

        for app in doZamkniecia() { app.terminate() }

        let koniec = Date().addingTimeInterval(limit)
        while Date() < koniec, !doZamkniecia().isEmpty {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }

        return doZamkniecia().compactMap { $0.localizedName }
    }

    // MARK: - Restart

    /// Restart ścieżką wylogowania, a nie `shutdown -r`.
    ///
    /// `shutdown -r` ubija sesję z boku; loginwindow nie przechodzi wtedy pełnego
    /// wylogowania i potrafi mimo ustawienia zostawić stan okien.
    ///
    /// 🔴 `with state saving preference` **nie jest ozdobnikiem**. Słownik System
    /// Events mówi wprost: *„If «state saving preference» is omitted or false,
    /// state is always saved."* Gołe `restart` zapisuje stan sesji niezależnie od
    /// `TALLogoutSavesState`, więc do 0.1.7 czysty start nie miał prawa działać —
    /// i nie działał. Z parametrem loginwindow pyta o preferencję użytkownika,
    /// czyli o tę, którą program przed chwilą ustawił.
    /// Polecenie restartu wystawione osobno, żeby sprawdzian headless mógł je
    /// przeczytać bez restartowania maszyny.
    static let restartScript =
        "tell application \"System Events\" to restart with state saving preference"

    static func restart() throws {
        _ = try AppleScript.run(restartScript)
    }

    // MARK: - Wysuwanie

    /// Wysuwa **cały dysk fizyczny**, na którym leży wskazany system.
    ///
    /// Finder wysuwa sam wolumin systemowy i zostawia zamontowany wolumin danych
    /// (`nobrowse`), przez co po wyjęciu wtyczki macOS zgłasza złe odmontowanie
    /// i zawiesza wejście-wyjście. Tutaj schodzimy do nośnika i wyrzucamy wszystko.
    static func eject(_ system: BootSystem) throws {
        // Świeżość przed czasem: wysuwanie schodzi do nośnika po trzech szczeblach
        // APFS-a i pół sekundy starego odczytu mogłoby wskazać nie ten dysk.
        DiskUtility.zapomnij()

        if let current = SystemScanner.current(), current.volumeUUID == system.volumeUUID {
            throw BootError.refusedRunningSystem(system.name)
        }
        guard FileManager.default.fileExists(atPath: system.mountPoint) else {
            throw BootError.volumeUnavailable(system.name)
        }
        guard let disk = system.wholeDisk else {
            throw BootError.ejectFailed(disk: system.name,
                                        message: String(localized: "Could not determine the physical disk."),
                                        blockers: [])
        }
        if DiskUtility.bool(disk, "Internal") == true {
            throw BootError.refusedInternalDisk(system.name)
        }

        let volumes = DiskUtility.mountedVolumes(inContainerOf: system.mountPoint)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", disk]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BootError.ejectFailed(disk: disk, message: message,
                                        blockers: processesHolding(volumes))
        }
    }

    /// Nazwy procesów trzymających otwarte pliki na podanych woluminach.
    private static func processesHolding(_ volumes: [String]) -> [String] {
        guard !volumes.isEmpty,
              let data = DiskUtility.run("/usr/sbin/lsof", ["-t", "-w"] + volumes),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let pids = text.split(separator: "\n").prefix(20)
        var names: Set<String> = []
        for pid in pids {
            guard let out = DiskUtility.run("/bin/ps", ["-o", "comm=", "-p", String(pid)]),
                  let name = String(data: out, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            names.insert((name as NSString).lastPathComponent)
        }
        return names.sorted()
    }
}
