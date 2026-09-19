import Foundation

/// Cienka warstwa nad `diskutil info -plist`.
///
/// Foundation potrafi podać nazwę i UUID woluminu, ale nie zna pojęć APFS-a:
/// kontenera, magazynu fizycznego ani dysku nadrzędnego. Bez nich nie da się
/// odpowiedzieć na pytanie „który dysk fizyczny mam wysunąć", a to właśnie ono
/// stoi za komunikatem „dysk został źle odmontowany".
enum DiskUtility {

    // MARK: - Pamięć podręczna

    /// Jedno `diskutil info` kosztuje **224 ms** — zmierzone 2026-09-19.
    ///
    /// 🔴 Bez pamięci podręcznej jedno odświeżenie listy kosztowało sześć takich
    /// uruchomień i **1 308 ms**, bo `system(atVolume:)` pytało o ten sam wolumin
    /// dwa razy (raz o `Bootable`, raz o resztę), a `current()` leciało jeszcze
    /// dwa razy osobno. Znalezisko P1-02 i P2-12 z audytu 2026-09-19.
    ///
    /// Pamięć ma **termin ważności**, a nie ręczne kasowanie, i to jest świadome:
    /// `diskutil` opisuje stan sprzętu, więc zapamiętany odczyt musi się sam
    /// przeterminować. Ręczne unieważnianie znaczyłoby, że każde nowe miejsce
    /// wywołania musi pamiętać o wyczyszczeniu — a to jest dokładnie ten rodzaj
    /// umowy, o którym się zapomina. Pół sekundy starczy na jedno przejście
    /// skanowania (≈250 ms) i jest krótsze niż jakakolwiek reakcja człowieka.
    private static let terminWaznosci: TimeInterval = 0.5
    private static let zamek = NSLock()
    private static var pamiec: [String: (czas: Date, dane: [String: Any]?)] = [:]

    /// Kasuje zapamiętane odczyty. Wołane tam, gdzie świeżość jest ważniejsza
    /// niż czas — przed wysuwaniem nośnika.
    static func zapomnij() {
        zamek.lock(); defer { zamek.unlock() }
        pamiec.removeAll()
    }

    /// Słownik `diskutil info` dla ścieżki woluminu albo identyfikatora (`disk5s2`).
    ///
    /// Odczyt nieudany jest zapamiętywany tak samo jak udany: wolumin, który nie
    /// jest woluminem, nie ma się o to pytać sześć razy pod rząd.
    static func info(_ target: String) -> [String: Any]? {
        zamek.lock()
        if let wpis = pamiec[target], Date().timeIntervalSince(wpis.czas) < terminWaznosci {
            zamek.unlock()
            return wpis.dane
        }
        zamek.unlock()

        var wynik: [String: Any]?
        if let data = run("/usr/sbin/diskutil", ["info", "-plist", target]) {
            wynik = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        }

        zamek.lock()
        pamiec[target] = (Date(), wynik)
        zamek.unlock()
        return wynik
    }

    static func string(_ target: String, _ key: String) -> String? {
        info(target)?[key] as? String
    }

    static func bool(_ target: String, _ key: String) -> Bool? {
        info(target)?[key] as? Bool
    }

    /// Dysk fizyczny, na którym leży wolumin.
    ///
    /// Droga wiedzie przez trzy szczeble, bo `ParentWholeDisk` woluminu APFS
    /// wskazuje dysk *syntetyczny* (kontener), a nie nośnik:
    ///
    ///     /Volumes/Mac Lab → disk5 (kontener) → disk4s2 (magazyn) → disk4 (nośnik)
    ///
    /// Wysunięcie kontenera zostawia nośnik podłączony — stąd ta pełna droga.
    static func wholeDisk(forVolumeAt path: String) -> String? {
        guard let container = string(path, "APFSContainerReference") else {
            // Wolumin spoza APFS-a: nośnik jest bezpośrednim rodzicem.
            return string(path, "ParentWholeDisk")
        }
        guard let stores = info(container)?["APFSPhysicalStores"] as? [[String: Any]],
              let store = stores.first?["APFSPhysicalStore"] as? String else { return nil }
        return string(store, "ParentWholeDisk")
    }

    /// Punkty montowania wszystkich woluminów tego samego kontenera APFS.
    ///
    /// Enumeracja idzie **bez** `.skipHiddenVolumes`. Ta opcja gubi wolumin danych
    /// instalacji systemu, montowany z flagą `nobrowse` — zmierzone 2026-09-18:
    /// bez opcji lista zawiera `/Volumes/Mac Lab - Data`, z opcją już nie.
    /// Na tej samej ślepocie stoi Finder, który wysuwa sam wolumin systemowy
    /// i zostawia dysk podłączony.
    static func mountedVolumes(inContainerOf path: String) -> [String] {
        guard let container = string(path, "APFSContainerReference") else { return [path] }
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: []) ?? []
        return mounted
            .map(\.path)
            .filter { string($0, "APFSContainerReference") == container }
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
