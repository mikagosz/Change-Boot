import Foundation

/// Cienka warstwa nad `diskutil info -plist`.
///
/// Foundation potrafi podać nazwę i UUID woluminu, ale nie zna pojęć APFS-a:
/// kontenera, magazynu fizycznego ani dysku nadrzędnego. Bez nich nie da się
/// odpowiedzieć na pytanie „który dysk fizyczny mam wysunąć", a to właśnie ono
/// stoi za komunikatem „dysk został źle odmontowany".
enum DiskUtility {

    /// Słownik `diskutil info` dla ścieżki woluminu albo identyfikatora (`disk5s2`).
    static func info(_ target: String) -> [String: Any]? {
        guard let data = run("/usr/sbin/diskutil", ["info", "-plist", target]) else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
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
