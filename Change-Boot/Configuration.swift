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
    var monochromeMenuBarIcon: Bool { didSet { save() } }
    var hidesDockIcon: Bool { didSet { save() } }
    var cleanStartByDefault: Bool { didSet { save() } }
    var setupCompleted: Bool { didSet { save() } }

    /// Zwykły wpis logowania — program otwiera się przy każdym zalogowaniu.
    var launchAtLogin: Bool { didSet { save() } }
    /// Program otwiera się **raz**, po powrocie na ten system przełączeniem
    /// zrobionym tym programem. Szczegóły i uzasadnienie: `LoginItem`.
    var launchAfterSwitch: Bool { didSet { save() } }

    struct Entry: Codable, Identifiable, Hashable {
        let volumeUUID: String
        /// Ostatnia znana nazwa — tylko do pokazania, gdy dysku nie ma w pobliżu.
        var lastKnownName: String
        /// Kolor wybrany przez użytkownika. Opcjonalny, żeby konfiguracja zapisana
        /// przed wprowadzeniem kolorów nadal się wczytywała.
        var colorName: String?

        var id: String { volumeUUID }
        var color: SystemColor { SystemColor(rawValue: colorName ?? "") ?? .blue }
    }

    private let defaults: UserDefaults

    /// Nazwy kluczy są widoczne na zewnątrz, bo `AppDelegate` musi odczytać
    /// ustawienie paska menu, zanim powstanie model — decyduje o tym, czy
    /// zamknięcie okna ma zakończyć program.
    enum Key {
        static let entries = "entries"
        static let menuBar = "showsMenuBarIcon"
        static let monoMenuBar = "monochromeMenuBarIcon"
        static let hideDock = "hidesDockIcon"
        static let cleanStart = "cleanStartByDefault"
        static let setupDone = "setupCompleted"
        static let launchAtLogin = "launchAtLogin"
        static let launchAfterSwitch = "launchAfterSwitch"
        /// Znacznik jednorazowego wpisu logowania. Świadomie **nie** jest polem
        /// `Configuration`: pisze i czyta go `LoginItem` przy starcie i przed
        /// restartem, czyli poza cyklem zapisu ustawień.
        static let armedOnce = "loginItemArmedOnce"
    }

    init(defaults: UserDefaults = AppBundle.defaults) {
        self.defaults = defaults
        // Ikona w pasku menu domyślnie WYŁĄCZONA: program bywa używany przy
        // nagrywaniu ekranu, gdzie każdy dodatkowy element paska przeszkadza.
        self.showsMenuBarIcon = defaults.bool(forKey: Key.menuBar)
        // Domyślnie kolorowa: tak wygląda od 0.1.5 i tak została przyjęta.
        self.monochromeMenuBarIcon = defaults.bool(forKey: Key.monoMenuBar)
        // Domyślnie WYŁĄCZONE: zdjęcie programu z Docka to zmiana, której nikt się
        // nie spodziewa po instalacji. Włącza ją użytkownik świadomie.
        self.hidesDockIcon = defaults.bool(forKey: Key.hideDock)
        self.cleanStartByDefault = defaults.object(forKey: Key.cleanStart) as? Bool ?? true
        self.setupCompleted = defaults.bool(forKey: Key.setupDone)
        // Domyślnie WYŁĄCZONY: wpis logowania to zmiana w cudzym systemie
        // i włącza ją użytkownik świadomie.
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        // Domyślnie WŁĄCZONE, odwrotnie niż autostart: jednorazowe otwarcie po
        // powrocie jest tym, po co w ogóle wraca się na drugi system, a wpis
        // zdejmuje się sam przy najbliższym starcie. Poproszone wprost przez [U].
        self.launchAfterSwitch = defaults.object(forKey: Key.launchAfterSwitch) as? Bool ?? true

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
        entries.append(Entry(volumeUUID: system.volumeUUID,
                             lastKnownName: system.name,
                             colorName: nextFreeColor().rawValue))
        save()
    }

    /// Pierwszy kolor palety nieużywany na liście, żeby dwa dyski nie startowały
    /// z tym samym. Gdy paleta się wyczerpie, kolory zaczynają się powtarzać.
    private func nextFreeColor() -> SystemColor {
        let used = Set(entries.compactMap(\.colorName))
        return SystemColor.allCases.first { !used.contains($0.rawValue) } ?? .blue
    }

    func setColor(_ color: SystemColor, for entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.volumeUUID == entry.volumeUUID }) else { return }
        entries[index].colorName = color.rawValue
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
        defaults.set(monochromeMenuBarIcon, forKey: Key.monoMenuBar)
        defaults.set(hidesDockIcon, forKey: Key.hideDock)
        defaults.set(cleanStartByDefault, forKey: Key.cleanStart)
        defaults.set(setupCompleted, forKey: Key.setupDone)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(launchAfterSwitch, forKey: Key.launchAfterSwitch)
    }
}
