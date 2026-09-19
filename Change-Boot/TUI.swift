import Foundation

/// Interfejs pełnoekranowy w terminalu.
///
/// Czwarta droga tej samej binarki — obok okna, demona i zwykłego wiersza poleceń.
/// Wchodzi tylko przy **gołym** wywołaniu z terminala; każdy czasownik (`list`,
/// `switch`, `log`…) idzie dalej zwykłym tekstem i ma nietknięte kody wyjścia,
/// bo to umowa z cudzymi skryptami.
///
/// Wygląd wg specyfikacji [U] z 2026-09-19: patrz `Paleta` i plan w sejfie.
enum TUI {

    // MARK: - Stan

    /// Czynność czekająca na `ENTER`. Ekran zadaje w danej chwili **jedno**
    /// pytanie, więc to jest jedno pole, a nie dwa niezależne.
    ///
    /// 🔴 Niesie czynność, nie sam wolumin. Do 0.2.14 stał tu `BootSystem?`
    /// i wystarczał, bo potwierdzać dało się tylko przełączenie. Przy drugiej
    /// czynności takie pole odpowiada na pytanie „czego dotyczy", ale nie na
    /// „co ma się stać" — a od tego zależy, co zrobi `ENTER`.
    enum DoPotwierdzenia {
        case przelaczenie(BootSystem)
        case wysuniecie(BootSystem)

        var system: BootSystem {
            switch self {
            case .przelaczenie(let s), .wysuniecie(let s): return s
            }
        }
    }

    private struct Stan {
        var systemy: [BootSystem] = []
        var biezacy: BootSystem?
        var zaznaczony = 0
        var komunikat: (tekst: String, barwa: Int)?
        var potwierdzenie: DoPotwierdzenia?
        var pracuje = false
    }

    private static var stan = Stan()

    // MARK: - Wejście

    /// Zwraca kod wyjścia. Gdy terminal nie nadaje się na tryb surowy,
    /// oddaje robotę statycznemu powitaniu — bez słowa skargi, bo to nie awaria.
    static func uruchom() -> CommandLineTool.Kod {
        guard Terminal.czyTerminal, Terminal.wejdzWTrybSurowy() else {
            return CommandLineTool.powitanie()
        }
        defer { Terminal.przywroc() }

        odswiez()
        rysuj()

        petla: while true {
            switch Terminal.czytajKlawisz() {
            case .gora:
                if stan.potwierdzenie == nil, !stan.systemy.isEmpty {
                    stan.zaznaczony = (stan.zaznaczony - 1 + stan.systemy.count) % stan.systemy.count
                    stan.komunikat = nil
                }
            case .dol:
                if stan.potwierdzenie == nil, !stan.systemy.isEmpty {
                    stan.zaznaczony = (stan.zaznaczony + 1) % stan.systemy.count
                    stan.komunikat = nil
                }
            case .enter:
                if let czynnosc = stan.potwierdzenie {
                    stan.potwierdzenie = nil
                    switch czynnosc {
                    case .przelaczenie(let cel):
                        if przelacz(na: cel) { break petla }   // maszyna się restartuje
                    case .wysuniecie(let cel):
                        wysun(cel)
                    }
                } else if let cel = wybrany, !czyBiezacy(cel) {
                    // Odmowa z polityki pada przed pytaniem, nie po nim —
                    // tak samo jak przy wysuwaniu systemu bieżącego.
                    guard Polityka.czyWolnoStartowac(cel) else {
                        stan.komunikat = (BootError.refusedByPolicy(cel.name).localizedDescription,
                                          Paleta.ostrzezenie)
                        break
                    }
                    stan.potwierdzenie = .przelaczenie(cel)
                }
            case .escape:
                if stan.potwierdzenie != nil { stan.potwierdzenie = nil } else { break petla }
            case .znak(let z):
                switch z.lowercased().first {
                case "q": break petla
                case "r": stan.potwierdzenie = nil; stan.komunikat = nil; odswiez()
                case "e": poprosOWysuniecie()
                default:  break
                }
            case .inne:
                break
            case .przerwane:
                // Zmiana rozmiaru okna. Nic nie robimy tutaj — przerysowanie
                // na końcu obrotu samo weźmie nowy rozmiar z `Terminal.rozmiar`.
                break
            case .koniec:
                // Wejście zniknęło. Bez tego pętla kręciłaby procesor w kółko.
                break petla
            }
            rysuj()
        }
        return .ok
    }

    private static var wybrany: BootSystem? {
        stan.systemy.indices.contains(stan.zaznaczony) ? stan.systemy[stan.zaznaczony] : nil
    }

    private static func czyBiezacy(_ s: BootSystem) -> Bool {
        s.volumeUUID == stan.biezacy?.volumeUUID
    }

    /// Klawisz `E`. Odmowa dla systemu, z którego maszyna właśnie pracuje, pada
    /// **tutaj**, a nie dopiero przy wykonaniu: pytanie „na pewno wysunąć?",
    /// po którym i tak przychodzi odmowa, jest pytaniem o nic.
    /// Ta sama odmowa stoi drugi raz w `BootActions.eject` i tak ma zostać —
    /// wiersz poleceń i okno wchodzą tam własną drogą.
    private static func poprosOWysuniecie() {
        guard stan.potwierdzenie == nil, let cel = wybrany else { return }
        guard !czyBiezacy(cel) else {
            stan.komunikat = (BootError.refusedRunningSystem(cel.name).localizedDescription,
                              Paleta.ostrzezenie)
            return
        }
        stan.komunikat = nil
        stan.potwierdzenie = .wysuniecie(cel)
    }

    // MARK: - Dane

    private static func odswiez() {
        stan.pracuje = true
        rysuj()
        let konfiguracja = Configuration()
        let wykryte = SystemScanner.scan()
        stan.biezacy = SystemScanner.current()

        // Kolejność z konfiguracji użytkownika, a nie z tego, co akurat zwróciło
        // skanowanie — na liście w oknie stoją w tej samej kolejności.
        var lista = konfiguracja.entries.compactMap { wpis in
            wykryte.first { $0.volumeUUID == wpis.volumeUUID }
        }
        for system in wykryte where !lista.contains(where: { $0.volumeUUID == system.volumeUUID }) {
            lista.append(system)
        }
        stan.systemy = lista
        stan.zaznaczony = min(stan.zaznaczony, max(0, lista.count - 1))
        stan.pracuje = false
    }

    // MARK: - Działanie

    /// Zwraca `true`, gdy maszyna została poproszona o restart.
    private static func przelacz(na system: BootSystem) -> Bool {
        stan.pracuje = true
        rysuj()

        // 🔴 Bez pomocnika przełączenie wywołuje SYSTEMOWE okno hasła. Zanim
        // się pojawi, wracamy do zwykłego ekranu — okno dialogowe nad osobnym
        // ekranem terminala wygląda jak zawieszenie i nie wiadomo, co odpowiada.
        let bezPomocnika = !HelperClient.isReady
        if bezPomocnika { Terminal.przywroc() }
        defer { if bezPomocnika { Terminal.wejdzWTrybSurowy() } }

        let konfiguracja = Configuration()
        let czysty = konfiguracja.cleanStartByDefault
        do {
            let przyjeta = BootActions.setWindowRestore(!czysty)
            try BootActions.setStartupDisk(to: system)
            if czysty && !przyjeta {
                let oporne = BootActions.closeUserApps()
                if !oporne.isEmpty {
                    stan.komunikat = (CommandLineTool.t("These did not close: \(oporne.joined(separator: ", "))"),
                                      Paleta.ostrzezenie)
                    stan.pracuje = false
                    return false
                }
            }
            EventLog.zapisz(.przelaczenie, skutek: .udane, z: stan.biezacy, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen, szczegol: "TUI")
            if konfiguracja.launchAfterSwitch { LoginItem.uzbrojNaPowrot() }
            try BootActions.restart()
            return true
        } catch BootError.cancelled {
            EventLog.zapisz(.przelaczenie, skutek: .anulowane, z: stan.biezacy, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen, szczegol: "TUI")
            stan.komunikat = (CommandLineTool.t("Cancelled."), Paleta.drugi)
        } catch {
            EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: stan.biezacy, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen,
                            szczegol: error.localizedDescription)
            stan.komunikat = (error.localizedDescription, Paleta.blad)
        }
        stan.pracuje = false
        return false
    }

    /// Wysuwa **cały nośnik**, tak samo jak okno i `change-boot eject`.
    ///
    /// Na końcu odświeżenie listy, a nie samo przerysowanie: wysunięty dysk
    /// znika z `/Volumes` i zostawiony na ekranie kłamałby aż do `R`.
    private static func wysun(_ system: BootSystem) {
        stan.pracuje = true
        rysuj()
        do {
            try BootActions.eject(system)
            EventLog.zapisz(.wysuniecie, skutek: .udane, na: system,
                            zrodlo: .wierszPolecen, szczegol: "TUI")
            stan.komunikat = (CommandLineTool.t("Ejected the whole disk holding “\(system.name)”."),
                              Paleta.sukces)
        } catch {
            EventLog.zapisz(.wysuniecie, skutek: .nieudane, na: system,
                            zrodlo: .wierszPolecen, szczegol: error.localizedDescription)
            stan.komunikat = (error.localizedDescription, Paleta.blad)
        }
        stan.pracuje = false
        odswiez()
    }
}

// MARK: - Rysowanie

extension TUI {

    /// Szerokość treści. Zawężona, bo panel ma mieć powietrze po bokach,
    /// a przy bardzo szerokim oknie rozciągnięta ramka wygląda jak tabela.
    static var szerokosc: Int {
        min(66, max(40, Terminal.rozmiar.kolumny - 6))
    }

    /// 🔴 Cały ekran składa się w **jeden napis** i idzie jednym zapisem.
    ///
    /// Rysowanie wiersz po wierszu przez osobne `write` miga na oczach: terminal
    /// pokazuje połowę ramki, zanim doleci reszta. Jeden zapis to jedna klatka.
    ///
    /// 🔴 Każdy wiersz staje pod **własnym adresem** (`ESC[w;1H`), a nie przez
    /// znak końca linii po poprzednim. Dwa powody, oba widziane na ekranie:
    ///
    /// 1. Koniec linii w ostatnim wierszu okna przewija terminal o jeden i cały
    ///    widok wędruje w górę. Przy oknie niższym niż rysunek wędruje tyle razy,
    ///    ile brakuje wierszy — a po powiększeniu okna Terminal.app dokłada puste
    ///    wiersze u góry i widok zostaje przyklejony do dołu.
    /// 2. Wiersz szerszy od okna zawija się i przesuwa wszystko pod nim o jeden.
    ///
    /// Adresowanie bezwzględne znaczy: pierwszy wiersz rysunku jest pierwszym
    /// wierszem okna, cokolwiek działo się przedtem i jakkolwiek okno urosło.
    /// Zgłoszone przez [U] 2026-09-19: „otwiera się bardzo nisko".
    private static func rysuj() {
        Terminal.pisz(klatka(wysokosc: Terminal.rozmiar.wiersze))
    }

    /// Jedna klatka gotowa do zapisu. Osobno od `rysuj`, żeby sprawdzian
    /// `Testy/terminal` mógł ją policzyć bez malowania po czyimś ekranie.
    static func klatka(wysokosc: Int) -> String {
        var ekran = Terminal.wyczysc
        // Rysunek wyższy od okna nie ma jak się zmieścić. Ucinamy dół — to gubi
        // pasek klawiszy, ale nie rozsypuje reszty; przewijanie gubiłoby górę
        // i zostawiało widok w miejscu, w którym nikt go nie szukał.
        for (numer, wiersz) in zloz().prefix(max(0, wysokosc)).enumerated() {
            ekran += Terminal.wWierszu(numer + 1) + wiersz
        }
        return ekran
    }

    /// Jeden wiersz o pełnej szerokości, z tłem pomalowanym do samego końca.
    ///
    /// Tło maluje **program**, a nie profil Terminala — dlatego `#0D0F12` wygląda
    /// tak samo niezależnie od tego, jaki motyw ma ustawiony człowiek.
    static func pas(_ tresc: String = "", wciecie: Int = 3) -> String {
        // Ostatnia zapora: cokolwiek przyjdzie, wiersz ma mieć dokładnie tę
        // szerokość. Bez tego jeden za długi napis rozsypuje cały ekran, bo
        // terminal zawija go do następnego wiersza i wszystko schodzi o jeden.
        let pelna = szerokosc + 6
        let uzyte = wciecie + Paleta.szerokosc(tresc)
        let dopelnienie = String(repeating: " ", count: max(0, pelna - uzyte))
        return Paleta.pedzel(Paleta.tlo) + String(repeating: " ", count: wciecie)
             + tresc + Paleta.pedzel(Paleta.tlo) + dopelnienie + Paleta.zeruj
    }

    private static func zloz() -> [String] {
        var w: [String] = []
        let W = szerokosc

        // ── nagłówek ───────────────────────────────────────────────────────
        w.append(pas())
        w.append(pas(Paleta.pogrubienie + Paleta.pisak(Paleta.tekst) + "CHANGE-BOOT"
                     + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
                     + Paleta.pisak(Paleta.drugi) + "  " + AppVersion.short))
        w.append(pas(Paleta.pisak(Paleta.drugi) + CommandLineTool.t("Startup Disk Manager")))
        w.append(pas())
        w.append(pas(Paleta.pisak(Paleta.ramka) + String(repeating: "─", count: W)))
        w.append(pas())

        // ── lista ──────────────────────────────────────────────────────────
        w.append(pas(Paleta.pisak(Paleta.drugi) + CommandLineTool.t("STARTUP VOLUMES")))
        w.append(pas())

        if stan.systemy.isEmpty {
            w.append(pas(Paleta.pisak(Paleta.drugi)
                         + CommandLineTool.t("No system is on the list yet."), wciecie: 5))
            w.append(pas())
        }

        for (indeks, system) in stan.systemy.enumerated() {
            w.append(contentsOf: indeks == stan.zaznaczony
                     ? panel(system) : wierszZwykly(system))
            w.append(pas())
        }

        w.append(pas(Paleta.pisak(Paleta.ramka) + String(repeating: "─", count: W)))
        w.append(pas())

        // ── stan ───────────────────────────────────────────────────────────
        w.append(pas(stanProgramu()))
        w.append(pas())

        // ── pasek klawiszy ─────────────────────────────────────────────────
        w.append(pas(paskKlawiszy()))
        w.append(pas())
        return w
    }

    /// Wybrany dysk: prostokątny panel z akcentem. Jedyne miejsce, w którym
    /// wolno użyć niebieskiego — akcent znaczy „to jest zaznaczone", nie „ładnie".
    static func panel(_ system: BootSystem) -> [String] {
        let wnetrze = szerokosc - 2
        let A = Paleta.pisak(Paleta.akcent)
        var w: [String] = []

        w.append(pas(A + "┌" + String(repeating: "─", count: wnetrze) + "┐"))

        let kropka = czyBiezacy(system) ? Paleta.sukces : Paleta.akcent
        // Nazwa woluminu bywa długa — macOS pozwala na 255 znaków. Nieucięta
        // rozpycha panel poza ramkę; zmierzone sprawdzianem przy nazwie na 114
        // znaków: wiersz tytułu miał 122 kolumny przy panelu na 72.
        w.append(wierszPanelu(" " + Paleta.pisak(kropka) + "● " + Paleta.zeruj
                              + Paleta.pedzel(Paleta.tlo) + Paleta.pogrubienie
                              + Paleta.pisak(Paleta.tekst)
                              + skroc(system.name, do: wnetrze - 4)
                              + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)))

        w.append(wierszPanelu("   " + Paleta.pisak(Paleta.drugi)
                              + "macOS \(system.productVersion)"))

        w.append(wierszPanelu(""))

        let lewo = skroc(opisNosnika(system), do: max(8, wnetrze - 24))
        let prawo: String
        if czyBiezacy(system) {
            prawo = Paleta.pisak(Paleta.sukces) + "✓ " + CommandLineTool.t("CURRENT")
        } else if !Polityka.czyWolnoStartowac(system) {
            prawo = Paleta.pisak(Paleta.ostrzezenie) + "⊘ " + CommandLineTool.t("BLOCKED")
        } else {
            prawo = Paleta.pisak(Paleta.drugi) + "✓ " + CommandLineTool.t("BOOTABLE")
        }
        let luz = wnetrze - 4 - lewo.count - Paleta.szerokosc(prawo)
        w.append(wierszPanelu("   " + Paleta.pisak(Paleta.drugi) + lewo
                              + wypelnij(max(1, luz)) + prawo + " "))

        w.append(pas(A + "└" + String(repeating: "─", count: wnetrze) + "┘"))
        return w
    }

    /// Jeden wiersz wnętrza panelu: obramowanie, treść, dopełnienie, obramowanie.
    ///
    /// 🔴 Dopełnienie liczy się **tutaj, w jednym miejscu**. Pierwsza wersja miała
    /// je rozsypane po pięciu wierszach, każdy z własnym odejmowaniem — i każdy
    /// z nich mylił się o tę samą jedną kolumnę, przez co prawa krawędź panelu
    /// stała o znak lewiej niż `┐` i `┘`. Widać to dopiero na ekranie, a policzyć
    /// da się w sprawdzianie: patrz `Testy/terminal`, „każdy wiersz panelu ma
    /// tę samą szerokość".
    private static func wierszPanelu(_ tresc: String) -> String {
        let wnetrze = szerokosc - 2
        let A = Paleta.pisak(Paleta.akcent)
        let brak = wnetrze - Paleta.szerokosc(tresc)
        return pas(A + "│" + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
                   + tresc + wypelnij(brak) + A + "│")
    }

    /// Niewybrany dysk: bez ramki, przygaszony, z pustym kółkiem.
    private static func wierszZwykly(_ system: BootSystem) -> [String] {
        let znacznik = czyBiezacy(system) ? Paleta.sukces : Paleta.ramka
        return [
            pas(Paleta.pisak(znacznik) + "○ " + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
                + Paleta.pisak(Paleta.drugi) + skroc(system.name, do: szerokosc - 4),
                wciecie: 5),
            pas(Paleta.pisak(Paleta.ramka)
                + skroc("macOS \(system.productVersion) · " + opisNosnika(system),
                        do: szerokosc - 6),
                wciecie: 7),
        ]
    }

    private static func wypelnij(_ ile: Int) -> String {
        String(repeating: " ", count: max(0, ile))
    }

    /// „APFS · 498 GB available" — wolne miejsce liczone tak, jak pokazuje je
    /// Finder, czyli z uwzględnieniem tego, co system może zwolnić.
    private static func opisNosnika(_ system: BootSystem) -> String {
        let rodzaj = system.isInternal ? "Internal" : "External"
        guard let wartosci = try? URL(fileURLWithPath: system.mountPoint)
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let wolne = wartosci.volumeAvailableCapacityForImportantUsage else {
            return rodzaj
        }
        let formater = ByteCountFormatter()
        formater.countStyle = .file
        return "\(rodzaj) · \(formater.string(fromByteCount: wolne)) "
             + CommandLineTool.t("available")
    }

    private static func stanProgramu() -> String {
        if stan.pracuje {
            return Paleta.pisak(Paleta.ostrzezenie) + "● " + Paleta.zeruj
                 + Paleta.pedzel(Paleta.tlo) + Paleta.pisak(Paleta.ostrzezenie)
                 + CommandLineTool.t("WORKING")
        }
        if let czynnosc = stan.potwierdzenie {
            let nazwa = czynnosc.system.name
            let pytanie: String
            switch czynnosc {
            case .przelaczenie:
                pytanie = CommandLineTool.t("RESTART FROM “\(nazwa)”? ENTER to confirm, ESC to cancel")
            case .wysuniecie:
                pytanie = CommandLineTool.t("EJECT THE WHOLE DISK HOLDING “\(nazwa)”? ENTER to confirm, ESC to cancel")
            }
            return Paleta.pisak(Paleta.ostrzezenie) + "● " + Paleta.zeruj
                 + Paleta.pedzel(Paleta.tlo) + Paleta.pisak(Paleta.ostrzezenie) + pytanie
        }
        if let (tekst, barwa) = stan.komunikat {
            return Paleta.pisak(barwa) + "● " + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
                 + Paleta.pisak(barwa) + skroc(tekst, do: szerokosc - 2)
        }
        return Paleta.pisak(Paleta.sukces) + "● " + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
             + Paleta.pisak(Paleta.sukces) + CommandLineTool.t("SYSTEM READY")
    }

    /// Komunikat błędu bywa dłuższy niż ekran — ucinamy, zamiast rozsypywać układ.
    private static func skroc(_ tekst: String, do ile: Int) -> String {
        let jednaLinia = tekst.replacingOccurrences(of: "\n", with: " ")
        guard jednaLinia.count > ile else { return jednaLinia }
        return String(jednaLinia.prefix(max(0, ile - 1))) + "…"
    }

    private static func paskKlawiszy() -> String {
        func klawisz(_ znak: String, _ opis: String) -> String {
            Paleta.pisak(Paleta.tekst) + znak + Paleta.zeruj + Paleta.pedzel(Paleta.tlo)
            + Paleta.pisak(Paleta.drugi) + " " + opis + "    "
        }
        if stan.potwierdzenie != nil {
            return klawisz("ENTER", CommandLineTool.t("Confirm"))
                 + klawisz("ESC", CommandLineTool.t("Cancel"))
        }
        return klawisz("↑↓", CommandLineTool.t("Navigate"))
             + klawisz("ENTER", CommandLineTool.t("Boot"))
             + klawisz("E", CommandLineTool.t("Eject"))
             + klawisz("R", CommandLineTool.t("Refresh"))
             + klawisz("Q", CommandLineTool.t("Quit"))
    }
}
