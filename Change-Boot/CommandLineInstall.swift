import Foundation

/// Dowiązanie `change-boot` w `/usr/local/bin`, żeby wiersz poleceń dało się
/// wywołać nazwą, a nie całą ścieżką do wnętrza pakietu programu.
///
/// 🔴 **Świadomie NIE przez pomocnika.** Uprzywilejowany demon robi jedną rzecz
/// o ustalonym kształcie — woła `bless` na podanym punkcie montowania. Dołożenie
/// mu zapisu do katalogów systemowych zamieniłoby wąski most w ogólne „zrób coś
/// jako root", czyli dokładnie to, od czego uciekliśmy, zdejmując `// SKRÓT:`
/// z `PrivilegedShell`.
///
/// Zakładanie dowiązania to czynność **jednorazowa, przy konfiguracji**. Jedno
/// systemowe okno hasła jest tu uczciwszą ceną niż stałe poszerzenie uprawnień
/// procesu, który chodzi jako root przez cały czas pracy maszyny.
enum CommandLineInstall {

    /// Ścieżka dowiązania. `/usr/local/bin` jest w `PATH` powłoki logowanej
    /// i należy do roota — zmierzone, nie założone.
    static let sciezka = "/usr/local/bin/change-boot"

    /// Binarka programu, czyli cel dowiązania. Ta sama, która obsługuje okno
    /// i demona — wiersz poleceń jest jej trzecią rolą.
    static var cel: String {
        AppBundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Change-Boot").path
    }

    enum Stan: Equatable {
        case brak
        case zainstalowane
        /// Dowiązanie istnieje, ale pokazuje na inny pakiet — typowo na poprzednie
        /// miejsce programu po jego przeniesieniu.
        case wskazujeGdzieIndziej(String)
    }

    static var stan: Stan {
        guard let wskazuje = try? FileManager.default
            .destinationOfSymbolicLink(atPath: sciezka) else { return .brak }
        return wskazuje == cel ? .zainstalowane : .wskazujeGdzieIndziej(wskazuje)
    }

    static var opisStanu: String {
        switch stan {
        case .zainstalowane:
            return String(localized: "Installed — type change-boot in Terminal")
        case .wskazujeGdzieIndziej(let gdzie):
            return String(localized: "Points at another copy of the app: \(gdzie)")
        case .brak:
            return String(localized: "Not installed — the command has to be typed with its full path")
        }
    }

    // MARK: - Zmiany

    static func zainstaluj() throws {
        // Ścieżka pakietu może zawierać spacje i apostrofy — pojedyncze cudzysłowy
        // plus ucieczka apostrofu, tak samo jak przy `bless` przed pomocnikiem.
        let celWCudzyslowie = cytuj(cel)
        let dowiazanieWCudzyslowie = cytuj(sciezka)
        _ = try PrivilegedShell.run(
            "/bin/mkdir -p /usr/local/bin && /bin/ln -sf \(celWCudzyslowie) \(dowiazanieWCudzyslowie)")
    }

    static func usun() throws {
        // Kasujemy wyłącznie dowiązanie symboliczne i tylko pod znaną ścieżką —
        // żadnego `-r`, żadnego rozwijania wzorców.
        _ = try PrivilegedShell.run("/bin/rm -f \(cytuj(sciezka))")
    }

    private static func cytuj(_ sciezka: String) -> String {
        "'" + sciezka.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
