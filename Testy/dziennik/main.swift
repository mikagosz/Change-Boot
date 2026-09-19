// Sprawdzian headless dziennika zdarzeń i rozbioru argumentów wiersza poleceń.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-dziennik Testy/dziennik/main.swift \
//          Change-Boot/EventLog.swift Change-Boot/BootSystem.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/CommandLineTool.swift \
//          Change-Boot/BootActions.swift Change-Boot/PrivilegedShell.swift \
//          Change-Boot/HelperClient.swift Change-Boot/HelperProtocol.swift \
//          Change-Boot/Configuration.swift Change-Boot/SystemColor.swift \
//          Change-Boot/AppVersion.swift && /tmp/test-dziennik
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

print("\nRozpoznawanie polecenia")

sprawdz("znany czasownik to polecenie",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "list"]))
sprawdz("gołe słowo też, nawet nieznane — inaczej literówka po cichu otwiera okno",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "fruwaj"]))
// 🔴 Kontrola ujemna: to jest dokładnie ten przypadek, który nie może zostać
// wzięty za polecenie — macOS dokłada ten przełącznik przy uruchomieniu z Findera.
sprawdz("przełącznik systemowy NIE jest poleceniem",
        !CommandLineTool.czyPolecenie(["/x/Change-Boot", "-psn_0_12345"]))
sprawdz("brak argumentów NIE jest poleceniem",
        !CommandLineTool.czyPolecenie(["/x/Change-Boot"]))
sprawdz("--version jest poleceniem mimo myślnika",
        CommandLineTool.czyPolecenie(["/x/Change-Boot", "--version"]))

print("\nAwarie: \(awarie)")
exit(awarie == 0 ? 0 : 1)
