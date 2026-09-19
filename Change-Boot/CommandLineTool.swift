import Foundation

/// Wiersz poleceń — ta sama binarka, trzecia rola.
///
/// Po co: przełączenie dysku startowego jest jedyną czynnością tego programu,
/// której nie da się wyklikać z wyprzedzeniem. Pracownia testująca oprogramowanie
/// na kilku wersjach macOS chce to zrobić nocą, z harmonogramu, bez człowieka.
///
/// 🔴 **Granica, o której trzeba wiedzieć przed obiecaniem komukolwiek bezobsługowej
/// pracy.** `man bless`, sekcja dla Apple Silicon: *„Admin credentials may be prompted
/// when running bless on an Apple silicon platform… However, if the volume has been
/// previously blessed by a different OS instance, then these credentials may not be
/// necessary."* Czyli: pierwsze pobłogosławienie woluminu przechodzi człowiek,
/// kolejne mogą iść same. Z zainstalowanym pomocnikiem znika też pytanie o hasło
/// administratora po stronie programu.
enum CommandLineTool {

    /// Kody wyjścia. Ustalone, bo od nich zależy `if` w cudzym skrypcie —
    /// zmiana znaczenia którejkolwiek liczby psuje automatyzację po stronie klienta.
    enum Kod: Int32 {
        case ok = 0
        case blad = 1
        case zleUzycie = 2
        case brakWoluminu = 3
        case weryfikacjaNieprzeszla = 4
        case anulowane = 5
    }

    /// Czy argumenty w ogóle są poleceniem dla wiersza poleceń.
    ///
    /// Rozstrzyga **kształt pierwszego argumentu**, nie sama jego obecność: macOS
    /// dokłada uruchamianym programom własne przełączniki (`-psn_0_…`,
    /// `-NSDocumentRevisionsDebugMode`), a program otwarty z Findera ma pokazać
    /// okno, nie wypisać pomoc. Wszystkie te dokładki zaczynają się od myślnika.
    ///
    /// Gołe słowo na pierwszym miejscu jest więc poleceniem — także wtedy, gdy go
    /// nie znamy. Pierwsza wersja (0.2.0) przepuszczała nieznany czasownik dalej
    /// i program po cichu otwierał okno zamiast powiedzieć „nie znam takiego
    /// polecenia". W terminalu wyglądało to na zawieszenie.
    static func czyPolecenie(_ argumenty: [String]) -> Bool {
        guard let pierwszy = argumenty.dropFirst().first else { return false }
        if czasowniki.contains(pierwszy) { return true }
        return !pierwszy.hasPrefix("-")
    }

    private static let czasowniki: Set<String> = [
        "list", "current", "switch", "eject", "log", "help", "--help", "-h", "--version",
    ]

    // MARK: - Wejście

    static func main(_ argumenty: [String]) -> Never {
        var reszta = Array(argumenty.dropFirst())
        let czasownik = reszta.isEmpty ? "help" : reszta.removeFirst()
        let opcje = Opcje(reszta)

        switch czasownik {
        case "list":                   zakoncz(lista(opcje))
        case "current":                zakoncz(biezacy(opcje))
        case "switch":                 zakoncz(przelacz(opcje))
        case "eject":                  zakoncz(wysun(opcje))
        case "log":                    zakoncz(dziennik(opcje))
        case "--version":              print(AppVersion.short); zakoncz(.ok)
        case "help", "--help", "-h":   pomoc(); zakoncz(.ok)
        default:
            FileHandle.standardError.write(Data("Nieznane polecenie: \(czasownik)\n".utf8))
            pomoc()
            zakoncz(.zleUzycie)
        }
    }

    private static func zakoncz(_ kod: Kod) -> Never { exit(kod.rawValue) }

    /// Przełączniki i wolny argument (nazwa albo UUID systemu).
    struct Opcje {
        // Pola jawne, bo czyta je sprawdzian headless.
        let json: Bool
        let czystyStart: Bool?
        let zRestartem: Bool
        let limit: Int
        let cel: String?

        init(_ argumenty: [String]) {
            var cel: String?
            var limit = 20
            var czysty: Bool?
            var json = false
            var restart = false

            var i = 0
            while i < argumenty.count {
                let a = argumenty[i]
                switch a {
                case "--json":      json = true
                case "--clean":     czysty = true
                case "--no-clean":  czysty = false
                case "--restart":   restart = true
                case "--limit":
                    i += 1
                    if i < argumenty.count { limit = Int(argumenty[i]) ?? limit }
                default:
                    if !a.hasPrefix("-") && cel == nil { cel = a }
                }
                i += 1
            }
            self.json = json
            self.czystyStart = czysty
            self.zRestartem = restart
            self.limit = limit
            self.cel = cel
        }
    }

    // MARK: - Polecenia

    private static func lista(_ opcje: Opcje) -> Kod {
        let konfiguracja = Configuration()
        let wykryte = SystemScanner.scan()
        let biezacy = SystemScanner.current()

        struct Wiersz: Encodable {
            let nazwa: String, uuid: String, dostepny: Bool, biezacy: Bool
            let macOS: String?, urzadzenie: String?, zewnetrzny: Bool?
        }

        let wiersze: [Wiersz] = konfiguracja.entries.map { wpis in
            let system = wykryte.first { $0.volumeUUID == wpis.volumeUUID }
            return Wiersz(nazwa: system?.name ?? wpis.lastKnownName,
                          uuid: wpis.volumeUUID,
                          dostepny: system != nil,
                          biezacy: system?.volumeUUID == biezacy?.volumeUUID,
                          macOS: system?.productVersion,
                          urzadzenie: system?.deviceIdentifier,
                          zewnetrzny: system.map { !$0.isInternal })
        }

        if opcje.json { return wypiszJSON(wiersze) }

        guard !wiersze.isEmpty else {
            print("Żaden system nie jest skonfigurowany. Otwórz program i dodaj systemy.")
            return .ok
        }
        for w in wiersze {
            let znacznik = w.biezacy ? " ← bieżący" : (w.dostepny ? "" : "  (niepodłączony)")
            let opis = w.dostepny ? "macOS \(w.macOS ?? "?") · \(w.urzadzenie ?? "?")" : w.uuid
            print("\(w.nazwa)\(znacznik)\n    \(opis)")
        }
        return .ok
    }

    private static func biezacy(_ opcje: Opcje) -> Kod {
        struct Stan: Encodable {
            let nazwa: String?, uuid: String?, macOS: String?
            let urzadzenieStartowe: String?
        }
        let system = SystemScanner.current()
        let stan = Stan(nazwa: system?.name, uuid: system?.volumeUUID,
                        macOS: system?.productVersion,
                        urzadzenieStartowe: BootActions.currentStartupDevice())

        if opcje.json { return wypiszJSON(stan) }
        print("Pracujesz z: \(stan.nazwa ?? "?")  (macOS \(stan.macOS ?? "?"))")
        print("Firmware wystartuje z: /dev/\(stan.urzadzenieStartowe ?? "?")")
        return .ok
    }

    private static func przelacz(_ opcje: Opcje) -> Kod {
        guard let cel = opcje.cel else {
            FileHandle.standardError.write(Data("Podaj nazwę albo UUID systemu.\n".utf8))
            return .zleUzycie
        }
        guard let system = znajdz(cel) else {
            FileHandle.standardError.write(Data("Nie znaleziono podłączonego systemu: \(cel)\n".utf8))
            EventLog.zapisz(.przelaczenie, skutek: .nieudane, naNazwa: cel,
                            zrodlo: .wierszPolecen, szczegol: "nie znaleziono woluminu")
            return .brakWoluminu
        }

        let konfiguracja = Configuration()
        let czysty = opcje.czystyStart ?? konfiguracja.cleanStartByDefault
        let skad = SystemScanner.current()

        do {
            let preferencjaPrzyjeta = BootActions.setWindowRestore(!czysty)
            try BootActions.setStartupDisk(to: system)

            if czysty && !preferencjaPrzyjeta {
                let oporne = BootActions.closeUserApps()
                if !oporne.isEmpty {
                    let tekst = "Nie zamknęły się: \(oporne.joined(separator: ", "))"
                    FileHandle.standardError.write(Data("\(tekst)\n".utf8))
                    EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: skad, na: system,
                                    czystyStart: czysty, zrodlo: .wierszPolecen, szczegol: tekst)
                    return .blad
                }
            }

            EventLog.zapisz(.przelaczenie, skutek: .udane, z: skad, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen,
                            szczegol: opcje.zRestartem ? "z restartem" : "bez restartu")

            if opcje.zRestartem {
                try BootActions.restart()
            } else {
                print("Dysk startowy ustawiony na „\(system.name)”. Restart nie nastąpił — dodaj --restart.")
            }
            return .ok
        } catch BootError.cancelled {
            EventLog.zapisz(.przelaczenie, skutek: .anulowane, z: skad, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen)
            return .anulowane
        } catch let blad as BootError {
            FileHandle.standardError.write(Data("\(blad.localizedDescription)\n".utf8))
            EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: skad, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen,
                            szczegol: blad.localizedDescription)
            if case .verificationFailed = blad { return .weryfikacjaNieprzeszla }
            return .blad
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return .blad
        }
    }

    private static func wysun(_ opcje: Opcje) -> Kod {
        guard let cel = opcje.cel else {
            FileHandle.standardError.write(Data("Podaj nazwę albo UUID systemu.\n".utf8))
            return .zleUzycie
        }
        guard let system = znajdz(cel) else {
            FileHandle.standardError.write(Data("Nie znaleziono podłączonego systemu: \(cel)\n".utf8))
            return .brakWoluminu
        }
        do {
            try BootActions.eject(system)
            EventLog.zapisz(.wysuniecie, skutek: .udane, na: system, zrodlo: .wierszPolecen)
            print("Wysunięto cały nośnik z „\(system.name)”.")
            return .ok
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            EventLog.zapisz(.wysuniecie, skutek: .nieudane, na: system,
                            zrodlo: .wierszPolecen, szczegol: error.localizedDescription)
            return .blad
        }
    }

    private static func dziennik(_ opcje: Opcje) -> Kod {
        let wpisy = EventLog.ostatnie(opcje.limit)
        if opcje.json { return wypiszJSON(wpisy) }
        guard !wpisy.isEmpty else {
            print("Dziennik jest pusty: \(EventLog.plik.path)")
            return .ok
        }
        let formater = DateFormatter()
        formater.dateFormat = "yyyy-MM-dd HH:mm"
        for w in wpisy {
            let cel = w.naSystem.map { " → \($0)" } ?? ""
            let skad = w.zSystemu.map { " z \($0)" } ?? ""
            print("\(formater.string(from: w.czas))  \(w.czynnosc.rawValue)\(skad)\(cel)  [\(w.skutek.rawValue), \(w.zrodlo.rawValue)]")
            if let szczegol = w.szczegol { print("    \(szczegol)") }
        }
        return .ok
    }

    // MARK: - Pomocnicze

    /// Szuka po UUID, a dopiero potem po nazwie — UUID jest jednoznaczny, nazwa nie.
    private static func znajdz(_ cel: String) -> BootSystem? {
        let wykryte = SystemScanner.scan()
        if let po = wykryte.first(where: { $0.volumeUUID.caseInsensitiveCompare(cel) == .orderedSame }) {
            return po
        }
        return wykryte.first { $0.name.caseInsensitiveCompare(cel) == .orderedSame }
    }

    private static func wypiszJSON<T: Encodable>(_ wartosc: T) -> Kod {
        let koder = JSONEncoder()
        koder.dateEncodingStrategy = .iso8601
        koder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let dane = try? koder.encode(wartosc),
              let tekst = String(data: dane, encoding: .utf8) else { return .blad }
        print(tekst)
        return .ok
    }

    private static func pomoc() {
        print("""
        Change-Boot \(AppVersion.short) — przełącznik systemu startowego

        UŻYCIE
          change-boot <polecenie> [opcje]

        POLECENIA
          list                  skonfigurowane systemy i ich dostępność
          current               system, z którego pracujesz, i cel firmware'u
          switch <nazwa|UUID>   ustawia dysk startowy
          eject <nazwa|UUID>    wysuwa CAŁY nośnik, nie sam wolumin
          log                   ostatnie zdarzenia
          help                  ten opis

        OPCJE
          --json                wyjście do odczytu maszynowego
          --restart             po ustawieniu dysku uruchom ponownie
          --clean / --no-clean  czysty start; bez tego decyduje ustawienie programu
          --limit <n>           ile zdarzeń wypisać (domyślnie 20)

        KODY WYJŚCIA
          0 ok · 1 błąd · 2 złe użycie · 3 brak woluminu
          4 firmware nie przyjął celu · 5 anulowane

        UWAGA
          Bez zainstalowanego pomocnika każde przełączenie prosi o hasło
          administratora w systemowym oknie — także wtedy, gdy polecenie
          idzie z terminala. Pomocnika instaluje się w Opcjach programu.
        """)
    }
}
