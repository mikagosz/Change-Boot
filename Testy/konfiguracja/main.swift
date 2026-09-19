// Sprawdzian headless listy systemów i kolorów.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-konfiguracja Testy/konfiguracja/main.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/BootSystem.swift \
//          Change-Boot/Configuration.swift Change-Boot/SystemColor.swift \
//          Change-Boot/AppModel.swift Change-Boot/BootActions.swift \
//          Change-Boot/PrivilegedShell.swift Change-Boot/HelperClient.swift \
//          Change-Boot/HelperProtocol.swift Change-Boot/AppBundle.swift \
//          Change-Boot/LoginItem.swift Change-Boot/EventLog.swift \
//          Change-Boot/AppVersion.swift && /tmp/test-konfiguracja
//
// Pilnuje reguł, które już raz zostały złamane — patrz komentarze przy sprawdzianach.

import Foundation

var awarie = 0

func sprawdz(_ opis: String, _ warunek: @autoclosure () -> Bool) {
    if warunek() { print("  ✓ \(opis)") } else { print("  ✗ \(opis)"); awarie += 1 }
}

/// Osobna przegródka ustawień, żeby sprawdzian nie dotykał konfiguracji programu.
let suite = "com.mikagosz.ChangeBoot.testy"
UserDefaults.standard.removePersistentDomain(forName: suite)
guard let defaults = UserDefaults(suiteName: suite) else {
    print("✗ nie udało się otworzyć przegródki ustawień"); exit(1)
}

/// Czeka, aż `AppModel` skończy odczytywać dyski.
///
/// 🔴 Od 0.2.5 `refresh()` idzie **w tle** i wynik wraca na wątek główny
/// (znalezisko P1-02 z audytu: przedtem blokowało okno na 1,3 s). Sprawdzian musi
/// więc przepuścić pętlę główną, zamiast pytać o wynik od razu — inaczej mierzy
/// stan sprzed odczytu i wygląda to na usterkę modelu.
func poczekajNaSkan(_ model: AppModel, doSekund limit: TimeInterval = 15) -> Bool {
    let koniec = Date().addingTimeInterval(limit)
    while Date() < koniec {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if !model.skanowanie && !model.detected.isEmpty { return true }
    }
    return false
}

print("Lista systemów")

let model = AppModel(configuration: Configuration(defaults: defaults))
sprawdz("odczyt dysków kończy się w rozsądnym czasie (idzie w tle od 0.2.5)",
        poczekajNaSkan(model))

// USTERKA 2026-09-18: bieżący system pokazywał się dwa razy — u góry jako „ten
// system" i niżej, w „Inne znalezione systemy", z przyciskiem „Dodaj".
sprawdz("bieżący system jest zapisany od razu, bez klikania",
        model.current.map { model.configuration.contains($0) } == true)
sprawdz("bieżącego systemu NIE ma wśród nieskonfigurowanych",
        !model.unconfigured.contains { model.isCurrent($0) })
sprawdz("żaden wykryty system nie jest jednocześnie zapisany i nieskonfigurowany",
        model.unconfigured.allSatisfy { !model.configuration.contains($0) })

// Kontrola dodatnia: sprawdziany wyżej mają sens tylko wtedy, gdy jest co sprawdzać.
sprawdz("wykryto jakikolwiek system", !model.detected.isEmpty)
sprawdz("lista zapisanych nie jest pusta", !model.configuration.entries.isEmpty)

print("\nKolory")

let entries = model.configuration.entries
sprawdz("każdy wpis ma kolor", entries.allSatisfy { $0.colorName != nil })

if let first = entries.first {
    model.configuration.setColor(.red, for: first)
    sprawdz("zmiana koloru zostaje zapisana",
            model.configuration.entries.first?.color == .red)

    // Kolor trzyma się wpisu, a nie pozycji na liście: po ponownym wczytaniu
    // konfiguracji ma być ten sam.
    let reloaded = Configuration(defaults: defaults)
    sprawdz("kolor przeżywa ponowne wczytanie konfiguracji",
            reloaded.entries.first(where: { $0.volumeUUID == first.volumeUUID })?.color == .red)
}

if model.detected.count > 1 {
    for system in model.detected { model.configuration.add(system) }
    let uzyte = model.configuration.entries.compactMap(\.colorName)
    sprawdz("dwa systemy nie startują z tym samym kolorem",
            Set(uzyte).count == uzyte.count)
}

print("\nTrwałość wpisu odpiętego dysku")

// Odpięcie dysku nie może kasować konfiguracji — wpis ma zostać i doczekać
// ponownego podłączenia.
let widmo = BootSystem(volumeUUID: "00000000-0000-0000-0000-00000000FFFF",
                       name: "Dysk widmo", productVersion: "27.0",
                       mountPoint: "/Volumes/Dysk widmo",
                       deviceIdentifier: "disk99s1", isInternal: false)
model.configuration.add(widmo)
let poDodaniu = model.configuration.entries.count
_ = poczekajNaSkan(model)
let odswiezony = Configuration(defaults: defaults)
sprawdz("wpis niepodłączonego dysku przetrwał zapis i odczyt",
        odswiezony.entries.count == poDodaniu &&
        odswiezony.entries.contains { $0.volumeUUID == widmo.volumeUUID })
sprawdz("niepodłączony dysk nie udaje wykrytego",
        !model.detected.contains { $0.volumeUUID == widmo.volumeUUID })

UserDefaults.standard.removePersistentDomain(forName: suite)

print("\nAwarie: \(awarie)")
exit(awarie == 0 ? 0 : 1)
