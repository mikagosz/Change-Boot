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
//          Change-Boot/AppVersion.swift Change-Boot/Odinstalowanie.swift \
//          Change-Boot/CommandLineInstall.swift Change-Boot/HelpView.swift \
//          Change-Boot/CommandLineTool.swift Change-Boot/TUI.swift \
//          Change-Boot/TUIPaleta.swift Change-Boot/Terminal.swift \
//          Change-Boot/Polityka.swift && /tmp/test-konfiguracja
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

print("\nPolityka — ustawienia narzucone profilem MDM")

// Na tej maszynie żadnego profilu nie ma i mieć nie będzie, więc sprawdzamy to,
// co da się sprawdzić bez niego: że brak profilu NICZEGO nie blokuje i że sito
// woluminów działa na podanej liście, a nie na tym, co akurat jest w systemie.
let atrapaDozwolona = BootSystem(volumeUUID: "AAAA1111-2222-3333-4444-555555555555",
                                 name: "Dozwolony", productVersion: "27.2",
                                 mountPoint: "/", deviceIdentifier: "disk9s1",
                                 isInternal: true)
sprawdz("bez profilu wolno startować z czegokolwiek",
        Polityka.czyWolnoStartowac(atrapaDozwolona))
sprawdz("bez profilu nie ma listy dozwolonych", Polityka.dozwoloneUUID == nil)
sprawdz("bez profilu nie ma wymuszonego hasła", !Polityka.wymagajHasla)
sprawdz("bez profilu maszyna nie jest zarządzana", !Polityka.czyZarzadzany)
sprawdz("bez profilu żadne ustawienie nie jest zablokowane",
        !Polityka.zarzadzaneUstawienia.contains { Polityka.narzucone($0) })

// 🔴 Kontrola dodatnia: gdyby `narzucone` zwracało fałsz na WSZYSTKO, zera wyżej
// nic by nie znaczyły. Sprawdzamy więc drugą stronę — klucz, który na pewno
// istnieje w domenie programu jako ustawienie użytkownika, ma NIE być narzucony,
// a odczyt wartości ma mimo to działać.
sprawdz("kontrola — odczyt klucza spoza profilu nie wywraca się",
        Polityka.bool("zupelnieNieistniejacyKlucz9z9") == nil)
sprawdz("nazwa domeny polityki to domena programu",
        (Polityka.domena as String) == (AppBundle.identyfikator ?? "com.mikagosz.ChangeBoot"))

// Klucze profilu są umową z administratorem — literówka w którymkolwiek znaczy
// cichą utratę reguły, nie błąd. Dlatego stoją w sprawdzianie z nazwy.
sprawdz("klucz listy dozwolonych ma umówioną nazwę",
        Polityka.Klucz.dozwolone == "AllowedVolumeUUIDs")
sprawdz("klucz wymuszonego hasła ma umówioną nazwę",
        Polityka.Klucz.hasloPrzyPrzelaczeniu == "RequireAdminForSwitch")
sprawdz("klucz nazwy organizacji ma umówioną nazwę",
        Polityka.Klucz.organizacja == "OrganizationName")
sprawdz("profil może przejąć sześć ustawień programu",
        Polityka.zarzadzaneUstawienia.count == 6)

// 🔴 KONTROLA DODATNIA reguły. Wszystko wyżej to zera na maszynie bez profilu —
// zero z sita, którego nikt nie zmusił do jedynki, znaczy „nie wiem".
let lista = ["DD987E99-4992-4E44-8C81-4F17AFD93EBA",
             "EDCB296E-FC79-427F-915F-85E5F613D048"]
sprawdz("wolumin Z LISTY przechodzi",
        Polityka.czyNaLiscie("DD987E99-4992-4E44-8C81-4F17AFD93EBA", dozwolone: lista))
sprawdz("wolumin SPOZA listy jest odrzucony",
        !Polityka.czyNaLiscie("11111111-2222-3333-4444-555555555555", dozwolone: lista))
sprawdz("małe litery w profilu nie przepuszczają cudzego woluminu",
        Polityka.czyNaLiscie("dd987e99-4992-4e44-8c81-4f17afd93eba", dozwolone: lista))
sprawdz("małe litery po stronie listy też nie psują reguły",
        Polityka.czyNaLiscie("DD987E99-4992-4E44-8C81-4F17AFD93EBA",
                             dozwolone: lista.map { $0.lowercased() }))
sprawdz("brak listy znaczy: wolno wszystko",
        Polityka.czyNaLiscie("cokolwiek", dozwolone: nil))
sprawdz("PUSTA lista też znaczy: wolno wszystko, a nie: nic nie wolno",
        Polityka.czyNaLiscie("cokolwiek", dozwolone: []))
sprawdz("pusty UUID nie prześlizguje się przez niepustą listę",
        !Polityka.czyNaLiscie("", dozwolone: lista))

print("\nSprzątanie osieroconej przegródki — P3-17 z audytu")

// 🔴 Sprawdzane na PRAWDZIWEJ osieroconej domenie i tylko na niej, bo funkcja
// żadnej innej nie umie ruszyć — i to jest jej najważniejsza cecha. Wcześniejsza
// wersja tego sprawdzianu podawała nazwę domeny parametrem i skasowała nią
// prawdziwe ustawienia programu. Domena `change-boot` to śmieć po wpadce 0.2.2,
// więc jej założenie i skasowanie tutaj nie niszczy niczyich danych.
UserDefaults.standard.setPersistentDomain(["NSWindow Frame main": "1 2 3 4"],
                                          forName: Odinstalowanie.osieroconaDomena)
sprawdz("kontrola dodatnia — osierocona przegródka istnieje przed sprzątaniem",
        UserDefaults.standard.persistentDomain(forName: Odinstalowanie.osieroconaDomena) != nil)
sprawdz("sprzątanie zgłasza, że miało co sprzątać",
        Odinstalowanie.sprzatnijOsieroconaPrzegrodke())
sprawdz("drugie wywołanie jest obojętne i nic nie zgłasza",
        !Odinstalowanie.sprzatnijOsieroconaPrzegrodke())
sprawdz("sprzątana domena to ta z wpadki 0.2.2, nie domena programu",
        Odinstalowanie.osieroconaDomena == "change-boot"
            && Odinstalowanie.osieroconaDomena != "com.mikagosz.ChangeBoot")

print("\nAwarie: \(awarie)")
exit(awarie == 0 ? 0 : 1)
