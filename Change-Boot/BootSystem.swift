import Foundation

/// Instalacja macOS znaleziona na jakimś dysku.
///
/// Tożsamość niesie `volumeUUID`, nie nazwa. Nazwę woluminu użytkownik zmienia
/// jednym kliknięciem, a zapisana konfiguracja ma to przetrwać bez pytania go
/// o cokolwiek.
struct BootSystem: Identifiable, Hashable, Codable {
    let volumeUUID: String
    var name: String
    var productVersion: String
    var mountPoint: String
    var deviceIdentifier: String
    var isInternal: Bool

    var id: String { volumeUUID }

    /// Nazwa dysku fizycznego, na którym leży ten system (`disk4`).
    var wholeDisk: String? { DiskUtility.wholeDisk(forVolumeAt: mountPoint) }
}

enum SystemScanner {

    /// Wszystkie instalacje macOS widoczne w tej chwili, bieżąca na początku.
    ///
    /// Enumeracja **bez** `.skipHiddenVolumes` — z tą opcją znikają woluminy
    /// `nobrowse`. Tutaj akurat nie kryje się za nią żaden system, ale ta sama
    /// funkcja karmi wysuwanie dysku, gdzie pominięcie ich kosztuje komunikat
    /// „dysk został źle odmontowany".
    static func scan() -> [BootSystem] {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []

        let found = mounted.compactMap { system(atVolume: $0.path) }

        var unique: [String: BootSystem] = [:]
        for system in found where unique[system.volumeUUID] == nil {
            unique[system.volumeUUID] = system
        }

        let currentUUID = current()?.volumeUUID
        return unique.values.sorted {
            if $0.volumeUUID == currentUUID { return true }
            if $1.volumeUUID == currentUUID { return false }
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// System, z którego maszyna właśnie pracuje.
    static func current() -> BootSystem? { system(atVolume: "/") }

    /// Opisuje wolumin, jeśli leży na nim instalacja macOS. W przeciwnym razie `nil`.
    static func system(atVolume path: String) -> BootSystem? {
        guard let version = productVersion(atVolume: path) else { return nil }
        guard let info = DiskUtility.info(path),
              let uuid = info["VolumeUUID"] as? String,
              let device = info["DeviceIdentifier"] as? String else { return nil }

        let name = (info["VolumeName"] as? String) ?? (path as NSString).lastPathComponent
        let isInternal = (info["Internal"] as? Bool) ?? false

        return BootSystem(volumeUUID: uuid,
                          name: name,
                          productVersion: version,
                          mountPoint: path,
                          deviceIdentifier: device,
                          isInternal: isInternal)
    }

    /// Wersja macOS zapisana na woluminie — ona rozstrzyga, czy to system.
    ///
    /// Sprawdzenie idzie po pliku, nie po roli woluminu w APFS: rola mówi, jak
    /// wolumin jest użyty w kontenerze, a nie czy da się z niego wystartować.
    static func productVersion(atVolume path: String) -> String? {
        let plist = (path as NSString)
            .appendingPathComponent("System/Library/CoreServices/SystemVersion.plist")
        guard let data = FileManager.default.contents(atPath: plist),
              let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return dict["ProductVersion"] as? String
    }
}
