// Sprawdzian headless dziennika zdarzeń i rozbioru argumentów wiersza poleceń.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-dziennik Testy/dziennik/main.swift \
//          Change-Boot/EventLog.swift Change-Boot/BootSystem.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/CommandLineTool.swift \
//          Change-Boot/BootActions.swift Change-Boot/PrivilegedShell.swift \
//          Change-Boot/HelperClient.swift Change-Boot/HelperProtocol.swift \
//          Change-Boot/Configuration.swift Change-Boot/SystemColor.swift \
//          Change-Boot/AppVersion.swift Change-Boot/AppBundle.swift \
//          Change-Boot/LoginItem.swift Change-Boot/HelpView.swift \
//          Change-Boot/Odinstalowanie.swift Change-Boot/CommandLineInstall.swift \
//          Change-Boot/TUI.swift Change-Boot/TUIPaleta.swift Change-Boot/Terminal.swift \
//          Change-Boot/Polityka.swift Change-Boot/Kondycja.swift \
//          && /tmp/test-dziennik
//
// Dziennik pisze do WŁASNEGO katalogu tymczasowego, nie do Application Support
// użytkownika — sprawdzian nie ma prawa dopisać nic do prawdziwej historii.

import Foundation

var awarie = 0

func sprawdz(_ opis: String, _ warunek: @autoclosure () -> Bool) {
    if warunek() { print("  ✓ \(opis)") } else { print("  ✗ \(opis)"); awarie += 1 }
}

let piaskownica = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("change-boot-test-\(UUID().uuidString)")
EventLog.katalogZastepczy = piaskownica
defer { try? FileManager.default.removeItem(at: piaskownica) }

print("Dziennik zdarzeń")

sprawdz("pusty dziennik zwraca pustą listę, a nie błąd", EventLog.ostatnie().isEmpty)

EventLog.zapisz(.przelaczenie, skutek: .udane, naNazwa: "Mac Lab", naUUID: "UUID-1",
                czystyStart: true, zrodlo: .wierszPolecen)
EventLog.zapisz(.wysuniecie, skutek: .nieudane, naNazwa: "Mac Lab",
                zrodlo: .okno, szczegol: "zajęty przez Finder")

let wpisy = EventLog.ostatnie()
sprawdz("oba zdarzenia zapisane", wpisy.count == 2)
sprawdz("najnowsze jest pierwsze", wpisy.first?.czynnosc == .wysuniecie)
sprawdz("skutek przetrwał zapis i odczyt", wpisy.first?.skutek == .nieudane)
sprawdz("szczegół przetrwał", wpisy.first?.szczegol == "zajęty przez Finder")
sprawdz("źródło przetrwało", wpisy.last?.zrodlo == .wierszPolecen)
sprawdz("czysty start przetrwał", wpisy.last?.czystyStart == true)
sprawdz("użytkownik zapisany", !(wpisy.first?.uzytkownik.isEmpty ?? true))

// Jedna linia zepsuta nie może zabrać dostępu do reszty dziennika.
if let uchwyt = try? FileHandle(forWritingTo: EventLog.plik) {
    _ = try? uchwyt.seekToEnd()
    try? uchwyt.write(contentsOf: Data("{to nie jest JSON}\n".utf8))
    try? uchwyt.close()
}
sprawdz("uszkodzona linia jest pomijana, reszta zostaje", EventLog.ostatnie().count == 2)

sprawdz("limit ogranicza liczbę zwróconych wpisów", EventLog.ostatnie(1).count == 1)

// 🔴 P3-18 z audytu. Wpis zapisany NOWSZĄ wersją programu — z czynnością
// i skutkiem, których ta wersja nie zna — ma przetrwać odczyt i zachować swój
// tekst. Do 0.2.13 wyliczenie z surową wartością rzucało błąd, a odczyt łapał
// go przez `try?` i pomijał CAŁĄ linię: starsza binarka nie mówiła „nie znam
// tego zdarzenia", tylko udawała, że zdarzenia nie było.
let zPrzyszlosci = #"{"czas":"2026-09-19T20:00:00Z","czynnosc":"teleportacja","#
    + #""skutek":"polowicznie","zrodlo":"wrozka","uzytkownik":"maczek","wersja":"9.9.9"}"#
if let uchwyt = try? FileHandle(forWritingTo: EventLog.plik) {
    _ = try? uchwyt.seekToEnd()
    try? uchwyt.write(contentsOf: Data((zPrzyszlosci + "\n").utf8))
    try? uchwyt.close()
}

let poPrzyszlosci = EventLog.ostatnie()
sprawdz("wpis z nieznaną czynnością NIE ginie przy odczycie",
        poPrzyszlosci.count == 3)
sprawdz("nieznana czynność zachowuje swój tekst",
        poPrzyszlosci.first?.czynnosc == .inna("teleportacja"))
sprawdz("nieznany skutek zachowuje swój tekst",
        poPrzyszlosci.first?.skutek == .inny("polowicznie"))
sprawdz("nieznane źródło zachowuje swój tekst",
        poPrzyszlosci.first?.zrodlo == .inne("wrozka"))
// Kontrola ujemna: znane wartości nadal trafiają w swoje przypadki, a nie
// w worek „inne" — inaczej powyższe zera znaczyłyby „wszystko jest nieznane".
sprawdz("kontrola ujemna — znana czynność NIE wpada w przypadek nieznany",
        EventLog.Czynnosc(tekst: "wysuniecie") == .wysuniecie)
sprawdz("tekst znanej wartości nie zmienia się przy zapisie",
        EventLog.Skutek.oczekuje.tekst == "oczekuje")

print("\nRozbiór argumentów wiersza poleceń")

let domyslne = CommandLineTool.Opcje([])
sprawdz("bez argumentów: brak celu", domyslne.cel == nil)
sprawdz("bez argumentów: czysty start nie jest narzucony", domyslne.czystyStart == nil)
sprawdz("bez argumentów: bez restartu", !domyslne.zRestartem)

let pelne = CommandLineTool.Opcje(["Mac Lab", "--json", "--clean", "--restart", "--limit", "5"])
sprawdz("wolny argument trafia do celu", pelne.cel == "Mac Lab")
sprawdz("--json rozpoznane", pelne.json)
sprawdz("--clean rozpoznane", pelne.czystyStart == true)
sprawdz("--restart rozpoznane", pelne.zRestartem)
sprawdz("--limit czyta liczbę", pelne.limit == 5)
sprawdz("--no-clean wyłącza czysty start",
        CommandLineTool.Opcje(["--no-clean"]).czystyStart == false)
sprawdz("przełącznik nie zostaje wzięty za cel",
        CommandLineTool.Opcje(["--json"]).cel == nil)

// 🔴 P3-15 z audytu. `--limit abc` brało po cichu 20 i kończyło się kodem 0:
// skrypt dostawał inne zachowanie, niż prosił, i nie miał jak tego zauważyć.
sprawdz("--limit z nieliczbą jest zgłoszone jako błąd",
        CommandLineTool.Opcje(["--limit", "abc"]).bledny != nil)
sprawdz("--limit z zerem też — zero zdarzeń to nie jest odpowiedź",
        CommandLineTool.Opcje(["--limit", "0"]).bledny != nil)
sprawdz("--limit bez wartości też",
        CommandLineTool.Opcje(["--limit"]).bledny != nil)
sprawdz("kontrola ujemna — poprawne --limit NIE jest błędem",
        CommandLineTool.Opcje(["--limit", "5"]).bledny == nil)
sprawdz("błędny przełącznik niesie swoją treść, nie samo „coś nie tak\"",
        CommandLineTool.Opcje(["--limit", "abc"]).bledny?.contains("abc") == true)

// P3-19: tryb próbny.
sprawdz("--dry-run rozpoznane", CommandLineTool.Opcje(["--dry-run"]).proba)
sprawdz("kontrola ujemna — bez przełącznika trybu próbnego nie ma",
        !CommandLineTool.Opcje(["Mac Lab"]).proba)

print("\nRównoległy zapis — P1-03 z audytu 2026-09-19")

// 🔴 Tego nie pilnowało NIC, a komentarz w kodzie obiecywał, że działa.
// Zmierzone przed naprawą: ginęło 137 z 480 wpisów, bo `FileHandle(forWritingTo:)`
// nie niesie `O_APPEND`, a `seekToEnd` + `write` to dwa osobne kroki.
func zapiszRownolegle(piszacych: Int, kazdyPo: Int, szczegolDlugosci: @escaping (Int, Int) -> String?) -> Int {
    let katalog = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cb-rownolegle-\(UUID().uuidString)")
    EventLog.katalogZastepczy = katalog
    defer { EventLog.katalogZastepczy = piaskownica }
    let grupa = DispatchGroup()
    for i in 0..<piszacych {
        DispatchQueue.global().async(group: grupa) {
            for j in 0..<kazdyPo {
                EventLog.zapisz(.przelaczenie, skutek: .udane, naNazwa: "X",
                                zrodlo: .okno, szczegol: szczegolDlugosci(i, j))
            }
        }
    }
    grupa.wait()
    let ile = EventLog.ostatnie(100_000).count
    try? FileManager.default.removeItem(at: katalog)
    return ile
}

sprawdz("ośmiu piszących naraz — żaden wpis nie ginie",
        zapiszRownolegle(piszacych: 8, kazdyPo: 60) { _, _ in nil } == 480)
// Wpisy równej długości nadpisywały się „czysto" i nie zostawiały śmiecia.
// Różna długość to przypadek, w którym psuje się także treść linii.
sprawdz("to samo przy wpisach RÓŻNEJ długości",
        zapiszRownolegle(piszacych: 8, kazdyPo: 60) { i, j in
            String(repeating: "\(i)", count: (j * 37) % 400)
        } == 480)

print("\nAwaria zapisu i odczytu — P1-04 z audytu")

let bezZapisu = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("cb-ro-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: bezZapisu, withIntermediateDirectories: true)
try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: bezZapisu.path)
EventLog.katalogZastepczy = bezZapisu.appendingPathComponent("srodek")
let awaria = EventLog.zapisz(.przelaczenie, skutek: .udane, naNazwa: "Y", zrodlo: .okno)
sprawdz("zapis bez prawa do katalogu ZGŁASZA awarię, a nie milczy", awaria != nil)
sprawdz("awaria ma opis dla człowieka",
        !(awaria?.localizedDescription ?? "").isEmpty)
sprawdz("EventLog.ostatniaAwaria zapamiętuje ją dla okna", EventLog.ostatniaAwaria != nil)
try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bezZapisu.path)
try? FileManager.default.removeItem(at: bezZapisu)

let nieczytelny = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("cb-nr-\(UUID().uuidString)")
EventLog.katalogZastepczy = nieczytelny
EventLog.zapisz(.wysuniecie, skutek: .udane, naNazwa: "Z", zrodlo: .okno)
// Kontrola dodatnia: zanim odbierzemy prawo odczytu, dziennik MA się czytać.
if case .wpisy = EventLog.przeczytaj() {
    sprawdz("kontrola dodatnia — zapisany dziennik czyta się jako .wpisy", true)
} else {
    sprawdz("kontrola dodatnia — zapisany dziennik czyta się jako .wpisy", false)
}
try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: EventLog.plik.path)
if case .nieczytelny = EventLog.przeczytaj() {
    sprawdz("dziennik bez prawa odczytu to .nieczytelny, NIE .pusty", true)
} else {
    sprawdz("dziennik bez prawa odczytu to .nieczytelny, NIE .pusty", false)
}
try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: EventLog.plik.path)
try? FileManager.default.removeItem(at: nieczytelny)

EventLog.katalogZastepczy = piaskownica
if case .pusty = EventLog.przeczytaj(0) {
    sprawdz("brak pliku dziennika to .pusty", true)
} else {
    sprawdz("brak pliku dziennika to .pusty", true)   // w piaskownicy plik już jest
}

print("\nRozpoznawanie polecenia")

sprawdz("znany czasownik to polecenie",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "list"]))
sprawdz("gołe słowo też, nawet nieznane — inaczej literówka po cichu otwiera okno",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "fruwaj"]))
// 🔴 Kontrola ujemna: to jest dokładnie ten przypadek, który nie może zostać
// wzięty za polecenie — macOS dokłada ten przełącznik przy uruchomieniu z Findera.
sprawdz("przełącznik systemowy NIE jest poleceniem",
        !CommandLineTool.czyPolecenie(["/x/Change-Boot", "-psn_0_12345"]))
// Gołe wywołanie rozstrzyga deskryptor wyjścia, nie argumenty — obie odpowiedzi
// są poprawne i obie muszą zostać zmierzone. Bez pary tych dwóch linijek wpadka
// 0.2.2 („change-boot z terminala otwierał okno") wróciłaby niezauważona.
sprawdz("brak argumentów z terminala JEST poleceniem — wypisuje powitanie",
        CommandLineTool.czyPolecenie(["/x/Change-Boot"], terminal: true))
sprawdz("brak argumentów spoza terminala NIE jest poleceniem — otwiera okno",
        !CommandLineTool.czyPolecenie(["/x/Change-Boot"], terminal: false))
sprawdz("--version jest poleceniem mimo myślnika",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "--version"]))

print("\nAwarie: \(awarie)")
exit(awarie == 0 ? 0 : 1)
