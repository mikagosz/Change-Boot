import Foundation

enum BootError: LocalizedError {
    case volumeUnavailable(String)
    case blessFailed(String)
    case verificationFailed(expected: String, actual: String)
    case ejectFailed(disk: String, message: String, blockers: [String])
    case refusedInternalDisk(String)
    case refusedRunningSystem(String)
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
        guard FileManager.default.fileExists(atPath: system.mountPoint) else {
            throw BootError.volumeUnavailable(system.name)
        }

        let quoted = system.mountPoint.replacingOccurrences(of: "'", with: "'\\''")
        let output = try PrivilegedShell.run("/usr/sbin/bless --mount '\(quoted)' --setBoot 2>&1")

        // Sukces bless-a to za mało: sprawdzamy, na co naprawdę wskazuje firmware.
        let actual = currentStartupDevice()
        let expected = system.deviceIdentifier
        if let actual, actual != expected {
            throw BootError.verificationFailed(expected: expected, actual: actual)
        }
        _ = output
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
    static func setWindowRestore(_ enabled: Bool) {
        CFPreferencesSetValue("TALLogoutSavesState" as CFString,
                              enabled as CFBoolean,
                              "com.apple.loginwindow" as CFString,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize("com.apple.loginwindow" as CFString)
    }

    // MARK: - Restart

    /// Restart ścieżką wylogowania, a nie `shutdown -r`.
    ///
    /// `shutdown -r` ubija sesję z boku; loginwindow nie przechodzi wtedy pełnego
    /// wylogowania i potrafi mimo ustawienia zostawić stan okien.
    static func restart() throws {
        _ = try AppleScript.run("tell application \"System Events\" to restart")
    }

    // MARK: - Wysuwanie

    /// Wysuwa **cały dysk fizyczny**, na którym leży wskazany system.
    ///
    /// Finder wysuwa sam wolumin systemowy i zostawia zamontowany wolumin danych
    /// (`nobrowse`), przez co po wyjęciu wtyczki macOS zgłasza złe odmontowanie
    /// i zawiesza wejście-wyjście. Tutaj schodzimy do nośnika i wyrzucamy wszystko.
    static func eject(_ system: BootSystem) throws {
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
