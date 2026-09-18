import Foundation
import Observation

/// Zapamiętane systemy i ustawienia programu.
///
/// Trzyma **UUID** woluminów, nie nazwy ani ścieżki: zmiana nazwy dysku albo inna
/// kolejność montowania nie może rozsypać konfiguracji. Wpis, którego dysku nie ma
/// w tej chwili, zostaje na liście jako niedostępny — odpięcie dysku to nie powód,
/// żeby kasować konfigurację.
@Observable
final class Configuration {

    /// Systemy dodane przez użytkownika, w jego kolejności.
    private(set) var entries: [Entry] = []

    var showsMenuBarIcon: Bool { didSet { save() } }
    var cleanStartByDefault: Bool { didSet { save() } }
    var setupCompleted: Bool { didSet { save() } }

    struct Entry: Codable, Identifiable, Hashable {
        let volumeUUID: String
        /// Ostatnia znana nazwa — tylko do pokazania, gdy dysku nie ma w pobliżu.
        var lastKnownName: String
        var id: String { volumeUUID }
    }

    private let defaults: UserDefaults

    /// Nazwy kluczy są widoczne na zewnątrz, bo `AppDelegate` musi odczytać
    /// ustawienie paska menu, zanim powstanie model — decyduje o tym, czy
    /// zamknięcie okna ma zakończyć program.
    enum Key {
        static let entries = "entries"
        static let menuBar = "showsMenuBarIcon"
        static let cleanStart = "cleanStartByDefault"
        static let setupDone = "setupCompleted"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Ikona w pasku menu domyślnie WYŁĄCZONA: program bywa używany przy
        // nagrywaniu ekranu, gdzie każdy dodatkowy element paska przeszkadza.
        self.showsMenuBarIcon = defaults.bool(forKey: Key.menuBar)
        self.cleanStartByDefault = defaults.object(forKey: Key.cleanStart) as? Bool ?? true
        self.setupCompleted = defaults.bool(forKey: Key.setupDone)

        if let data = defaults.data(forKey: Key.entries),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            self.entries = decoded
        }
    }

    // MARK: - Zmiany listy

    func add(_ system: BootSystem) {
        guard !entries.contains(where: { $0.volumeUUID == system.volumeUUID }) else {
            refreshName(for: system)
            return
        }
        entries.append(Entry(volumeUUID: system.volumeUUID, lastKnownName: system.name))
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.volumeUUID == entry.volumeUUID }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func contains(_ system: BootSystem) -> Bool {
        entries.contains { $0.volumeUUID == system.volumeUUID }
    }

    /// Dopisuje aktualną nazwę do zapamiętanego wpisu — dysk mógł zostać przemianowany.
    func refreshName(for system: BootSystem) {
        guard let index = entries.firstIndex(where: { $0.volumeUUID == system.volumeUUID }),
              entries[index].lastKnownName != system.name else { return }
        entries[index].lastKnownName = system.name
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Key.entries)
        defaults.set(showsMenuBarIcon, forKey: Key.menuBar)
        defaults.set(cleanStartByDefault, forKey: Key.cleanStart)
        defaults.set(setupCompleted, forKey: Key.setupDone)
    }
}
