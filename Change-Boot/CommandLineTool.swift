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

    // MARK: - Napisy

    /// Pakiet, z którego wiersz poleceń bierze napisy.
    ///
    /// 🔴 Dwie pułapki naraz i obie były prawdziwą usterką (P1-05 z audytu 2026-09-19):
    ///
    /// 1. `String(localized:)` **bez** `bundle:` idzie do `Bundle.main`, a ten przy
    ///    uruchomieniu przez dowiązanie `/usr/local/bin/change-boot` nie jest
    ///    pakietem programu — patrz `AppBundle`. Bez tego parametru katalog ciągów
    ///    byłby niewidoczny i zostałyby same klucze.
    /// 2. Język wybrany **w programie** siedzi w przegródce programu, a proces
    ///    wiersza poleceń ma własną listę preferowanych języków. Dlatego wybrany
    ///    język podaje się wprost, wskazując katalog `.lproj`. Przy ustawieniu
    ///    „jak w systemie" zostaje zwykły pakiet i jego własne rozstrzyganie.
    private static let katalog: Bundle = {
        guard let kod = AppLanguage.current.code,
              let sciezka = AppBundle.main.path(forResource: kod, ofType: "lproj"),
              let wlasny = Bundle(path: sciezka) else { return AppBundle.main }
        return wlasny
    }()

    /// Napis z katalogu ciągów. Krótka nazwa, bo wchodzi w co drugą linijkę.
    static func t(_ klucz: String.LocalizationValue) -> String {
        String(localized: klucz, bundle: katalog)
    }

    /// To samo, ale prosto na standardowe wyjście błędów.
    private static func blad(_ tekst: String) {
        FileHandle.standardError.write(Data((tekst + "\n").utf8))
    }

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
    /// `terminal` wchodzi parametrem, żeby sprawdzian headless mógł zbadać obie
    /// odpowiedzi bez podszywania się pod deskryptor wyjścia.
    static func czyPolecenie(_ argumenty: [String],
                             terminal: Bool = isatty(STDOUT_FILENO) == 1) -> Bool {
        guard let pierwszy = argumenty.dropFirst().first else {
            // 🔴 Gołe wywołanie rozstrzyga **deskryptor wyjścia**, nie argumenty.
            // Z terminala `change-boot` ma powiedzieć, co umie; z Findera i z Docka
            // ma otworzyć okno. Do 0.2.2 obie drogi kończyły się oknem — a że proces
            // szedł wtedy przez dowiązanie w `/usr/local/bin`, okno wstawało bez
            // pakietu: po angielsku, od kreatora i z wersją „v.?".
            // Zgłoszone przez [U] 2026-09-19 zrzutem z terminala.
            return terminal
        }
        if czasowniki.contains(pierwszy) { return true }
        return !pierwszy.hasPrefix("-")
    }

    private static let czasowniki: Set<String> = [
        "list", "current", "switch", "eject", "volumes", "log", "uninstall",
        "help", "--help", "-h", "--version", "--plain",
    ]

    // MARK: - Wejście

    static func main(_ argumenty: [String]) -> Never {
        var reszta = Array(argumenty.dropFirst())
        // Gołe `change-boot` wita ekranem stanu, nie pełną listą przełączników:
        // [U] 2026-09-19 spodziewał się *„opisu, że jak wpiszesz to, to przyłączysz
        // się tu"* — czyli własnych dysków z gotowym poleceniem przy każdym,
        // a nie składni w nawiasach kątowych.
        let czasownik = reszta.isEmpty ? "powitanie" : reszta.removeFirst()
        let opcje = Opcje(reszta)

        // 🔴 Zły przełącznik kończy sprawę TUTAJ, kodem 2, zanim cokolwiek się
        // wydarzy. Przyjęcie wartości domyślnej w zastępstwie błędnej to cicha
        // zmiana zachowania — najgorszy rodzaj odpowiedzi dla skryptu.
        if let bledny = opcje.bledny {
            blad(t("Bad value for option: \(bledny)"))
            zakoncz(.zleUzycie)
        }

        switch czasownik {
        case "list":                   zakoncz(lista(opcje))
        case "current":                zakoncz(biezacy(opcje))
        case "switch":                 zakoncz(przelacz(opcje))
        case "eject":                  zakoncz(wysun(opcje))
        case "volumes":                zakoncz(woluminy(opcje))
        case "log":                    zakoncz(dziennik(opcje))
        case "uninstall":              zakoncz(odinstaluj(opcje))
        case "--version":              print(AppVersion.short); zakoncz(.ok)
        case "help", "--help", "-h":   pomoc(); zakoncz(.ok)
        // Gołe wywołanie z terminala otwiera interfejs pełnoekranowy; `--plain`
        // zostawia statyczne powitanie z 0.2.3, bo tryb surowy terminala to rzecz,
        // która w cudzym środowisku potrafi się nie udać.
        case "powitanie":              zakoncz(opcje.zwykly ? powitanie() : TUI.uruchom())
        case "--plain":                zakoncz(powitanie())
        default:
            blad(t("Unknown command: \(czasownik)"))
            pomoc()
            zakoncz(.zleUzycie)
        }
    }

    private static func zakoncz(_ kod: Kod) -> Never { exit(kod.rawValue) }

    /// Przełączniki i wolny argument (nazwa albo UUID systemu).
    struct Opcje {
        // Pola jawne, bo czyta je sprawdzian headless.
        let json: Bool
        /// Wyjście jako CSV. Osobno od `--json`, bo to dwa różne formaty dla
        /// dwóch różnych odbiorców: JSON dla skryptu, CSV dla arkusza.
        let csv: Bool
        /// Także woluminy systemowej hydrauliki APFS-a.
        let wszystkie: Bool
        let czystyStart: Bool?
        let zRestartem: Bool
        let limit: Int
        let cel: String?
        /// Bez interfejsu pełnoekranowego — sam tekst.
        let zwykly: Bool
        /// Tryb próbny: powiedz, co by się stało, i nie rób nic.
        let proba: Bool
        /// 🔴 Przełącznik, którego nie dało się przyjąć — razem z powodem.
        ///
        /// Do 0.2.13 `--limit abc` po cichu brało 20 i kończyło się kodem `0`.
        /// Skrypt dostawał inne zachowanie, niż prosił, i **nie miał jak tego
        /// zauważyć**. Znalezisko P3-15 z audytu 2026-09-19.
        let bledny: String?

        init(_ argumenty: [String]) {
            var cel: String?
            var limit = 20
            var czysty: Bool?
            var json = false
            var csv = false
            var wszystkie = false
            var restart = false
            var zwykly = false
            var proba = false
            var bledny: String?

            var i = 0
            while i < argumenty.count {
                let a = argumenty[i]
                switch a {
                case "--json":      json = true
                case "--csv":       csv = true
                case "--all":       wszystkie = true
                case "--plain":     zwykly = true
                case "--clean":     czysty = true
                case "--no-clean":  czysty = false
                case "--restart":   restart = true
                case "--dry-run":   proba = true
                case "--limit":
                    i += 1
                    guard i < argumenty.count else {
                        bledny = bledny ?? "--limit"
                        break
                    }
                    guard let liczba = Int(argumenty[i]), liczba > 0 else {
                        bledny = bledny ?? "--limit \(argumenty[i])"
                        break
                    }
                    limit = liczba
                default:
                    if !a.hasPrefix("-") && cel == nil { cel = a }
                }
                i += 1
            }
            self.json = json
            self.csv = csv
            self.wszystkie = wszystkie
            self.czystyStart = czysty
            self.zRestartem = restart
            self.limit = limit
            self.cel = cel
            self.zwykly = zwykly
            self.proba = proba
            self.bledny = bledny
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
            /// Czy profil konfiguracyjny pozwala z tego woluminu wystartować.
            /// Pole wchodzi do JSON-a zawsze, także bez profilu — skrypt ma
            /// czytać jedną stałą strukturę, nie zgadywać po obecności klucza.
            let dozwolony: Bool
        }

        let wiersze: [Wiersz] = konfiguracja.entries.map { wpis in
            let system = wykryte.first { $0.volumeUUID == wpis.volumeUUID }
            return Wiersz(nazwa: system?.name ?? wpis.lastKnownName,
                          uuid: wpis.volumeUUID,
                          dostepny: system != nil,
                          biezacy: system?.volumeUUID == biezacy?.volumeUUID,
                          macOS: system?.productVersion,
                          urzadzenie: system?.deviceIdentifier,
                          zewnetrzny: system.map { !$0.isInternal },
                          dozwolony: Polityka.dozwoloneUUID.map {
                              $0.contains(wpis.volumeUUID.uppercased())
                          } ?? true)
        }

        if opcje.json { return wypiszJSON(wiersze) }

        guard !wiersze.isEmpty else {
            print(t("No system is configured. Open the app and add the systems you want."))
            return .ok
        }
        for w in wiersze {
            var znacznik = w.biezacy ? t(" ← current") : (w.dostepny ? "" : t("  (not connected)"))
            if !w.dozwolony { znacznik += t("  (blocked by profile)") }
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
        print(t("Running from: \(stan.nazwa ?? "?")  (macOS \(stan.macOS ?? "?"))"))
        print(t("The firmware will start from: /dev/\(stan.urzadzenieStartowe ?? "?")"))
        return .ok
    }

    private static func przelacz(_ opcje: Opcje) -> Kod {
        guard let cel = opcje.cel else {
            blad(t("Give the name or the UUID of a system."))
            return .zleUzycie
        }
        guard let system = znajdz(cel) else {
            blad(t("No connected system found: \(cel)"))
            // 🔴 W trybie próbnym dziennik zostaje nietknięty także wtedy, gdy
            // woluminu nie ma. Sprawdzenie, czy polecenie w ogóle zadziała, nie
            // jest zdarzeniem i nie ma prawa zostawiać śladu (P3-19).
            if !opcje.proba {
                EventLog.zapisz(.przelaczenie, skutek: .nieudane, naNazwa: cel,
                                zrodlo: .wierszPolecen, szczegol: "nie znaleziono woluminu")
            }
            return .brakWoluminu
        }

        let konfiguracja = Configuration()
        let czysty = opcje.czystyStart ?? konfiguracja.cleanStartByDefault
        let skad = SystemScanner.current()

        if opcje.proba {
            print(t("Dry run — nothing was changed."))
            print(t("Would set the startup disk to “\(system.name)” (\(system.mountPoint))."))
            print(czysty ? t("Clean start: yes — open windows would not come back.")
                         : t("Clean start: no — open windows would come back."))
            print(opcje.zRestartem ? t("Would restart right after.")
                                   : t("Would not restart — add --restart."))
            return .ok
        }

        do {
            let preferencjaPrzyjeta = BootActions.setWindowRestore(!czysty)
            try BootActions.setStartupDisk(to: system)

            if czysty && !preferencjaPrzyjeta {
                let oporne = BootActions.closeUserApps()
                if !oporne.isEmpty {
                    let tekst = t("These did not close: \(oporne.joined(separator: ", "))")
                    blad(tekst)
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
                print(t("Startup disk set to “\(system.name)”. Nothing restarted — add --restart."))
            }
            return .ok
        } catch BootError.cancelled {
            EventLog.zapisz(.przelaczenie, skutek: .anulowane, z: skad, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen)
            return .anulowane
        } catch let usterka as BootError {
            blad(usterka.localizedDescription)
            EventLog.zapisz(.przelaczenie, skutek: .nieudane, z: skad, na: system,
                            czystyStart: czysty, zrodlo: .wierszPolecen,
                            szczegol: usterka.localizedDescription)
            if case .verificationFailed = usterka { return .weryfikacjaNieprzeszla }
            return .blad
        } catch {
            blad(error.localizedDescription)
            return .blad
        }
    }

    private static func wysun(_ opcje: Opcje) -> Kod {
        guard let cel = opcje.cel else {
            blad(t("Give the name or the UUID of a system."))
            return .zleUzycie
        }
        guard let system = znajdz(cel) else {
            blad(t("No connected system found: \(cel)"))
            return .brakWoluminu
        }
        if opcje.proba {
            print(t("Dry run — nothing was changed."))
            print(t("Would eject the whole disk holding “\(system.name)” (\(system.deviceIdentifier))."))
            return .ok
        }
        do {
            try BootActions.eject(system)
            EventLog.zapisz(.wysuniecie, skutek: .udane, na: system, zrodlo: .wierszPolecen)
            print(t("Ejected the whole disk holding “\(system.name)”."))
            return .ok
        } catch {
            blad(error.localizedDescription)
            EventLog.zapisz(.wysuniecie, skutek: .nieudane, na: system,
                            zrodlo: .wierszPolecen, szczegol: error.localizedDescription)
            return .blad
        }
    }

    /// Przegląd woluminów: co jest podpięte, na czym leży i co warto wiedzieć.
    ///
    /// Trzy wyjścia, bo trzech różnych odbiorców: człowiek przy terminalu czyta
    /// tekst, skrypt czyta JSON, a dział IT wkleja CSV do arkusza i rozsyła.
    /// Polecenie jest **wyłącznie odczytem** — nie dotyka dziennika, nie zmienia
    /// niczego, wolno je puścić z harmonogramu na całą flotę.
    private static func woluminy(_ opcje: Opcje) -> Kod {
        let przeglad = Kondycja.przeglad(wszystkie: opcje.wszystkie)

        if opcje.csv { print(Kondycja.csv(przeglad)); return .ok }
        if opcje.json { return wypiszJSON(przeglad) }

        guard !przeglad.isEmpty else {
            print(t("No mounted volume found."))
            return .ok
        }

        let formater = ByteCountFormatter()
        formater.countStyle = .file

        for w in przeglad {
            let miejsce = w.pojemnosc.map { pojemnosc -> String in
                let wolne = w.wolne.map { formater.string(fromByteCount: $0) } ?? "?"
                return "\(wolne) / \(formater.string(fromByteCount: pojemnosc))"
            } ?? "?"

            var cechy: [String] = []
            if let f = w.systemPlikow { cechy.append(f) }
            if w.sieciowy {
                cechy.append(t("network share"))
            } else {
                cechy.append(w.wewnetrzny == true ? t("internal") : t("external"))
            }
            if w.szyfrowany == true { cechy.append(t("encrypted")) }
            if w.startowy == true { cechy.append(t("bootable")) }

            // Udział sieciowy nie ma identyfikatora urządzenia i „(?)" obok
            // nazwy wygląda, jakby programowi coś nie wyszło.
            let gdzie = w.urzadzenie.map { "  (\($0))" } ?? ""
            print("\(w.nazwa)\(gdzie)")
            print("    \(cechy.joined(separator: " · "))  ·  \(miejsce) " + t("free"))
            if let n = w.nosnik {
                let opis = [n.nazwa, n.magistrala, n.ssd == true ? "SSD" : nil,
                            n.smart.map { "SMART: \($0)" }]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                print("    \(n.urzadzenie)  \(opis)")
            }
            for uwaga in w.uwagi { print("    ⚠︎ \(uwaga)") }
        }
        return .ok
    }

    private static func dziennik(_ opcje: Opcje) -> Kod {
        // Trzy przypadki, nie dwa: nieczytelny dziennik ma się różnić od pustego
        // także tutaj, i to kodem wyjścia — skrypt ma jak zauważyć (P1-04).
        let wpisy: [EventLog.Entry]
        switch EventLog.przeczytaj(opcje.limit) {
        case .wpisy(let w):
            wpisy = w
        case .pusty:
            if opcje.json { return wypiszJSON([EventLog.Entry]()) }
            print(t("The event log is empty: \(EventLog.plik.path)"))
            return .ok
        case .nieczytelny(let powod):
            blad(t("The event log at \(EventLog.plik.path) could not be read: \(powod)"))
            return .blad
        }
        if opcje.json { return wypiszJSON(wpisy) }
        let formater = DateFormatter()
        formater.dateFormat = "yyyy-MM-dd HH:mm"
        for w in wpisy {
            let cel = w.naSystem.map { " → \($0)" } ?? ""
            let skad = w.zSystemu.map { " z \($0)" } ?? ""
            print("\(formater.string(from: w.czas))  \(w.czynnosc.tekst)\(skad)\(cel)  [\(w.skutek.tekst), \(w.zrodlo.tekst)]")
            if let szczegol = w.szczegol { print("    \(szczegol)") }
        }
        return .ok
    }

    /// Zdejmuje demona, dowiązanie i wpis logowania.
    ///
    /// 🔴 Po co to w wierszu poleceń, skoro jest przycisk w Opcjach: bo przycisk
    /// znika razem z programem. Kto skasuje ikonę pierwszy, nie ma już czym
    /// posprzątać — a zostaje mu zarejestrowany demon roota. To polecenie działa
    /// dopóki binarka jest na dysku, także przez dowiązanie (P1-06 z audytu).
    private static func odinstaluj(_ opcje: Opcje) -> Kod {
        guard Odinstalowanie.cokolwiekZainstalowane else {
            print(t("Nothing to remove — Change-Boot has not installed anything outside its own app."))
            return .ok
        }

        let wynik = Odinstalowanie.wykonaj()

        func powiedz(_ co: String, _ stan: Odinstalowanie.Stan) {
            switch stan {
            case .zdjete:           print("  ✓ \(co)")
            case .nieBylo:          print("  — \(co): " + t("was not installed"))
            case .nieudane(let p):  blad("  ✗ \(co): \(p)")
            }
        }

        print(t("Removing what Change-Boot installed outside its own app:"))
        powiedz(t("login item"), wynik.wpisLogowania)
        powiedz(t("privileged helper"), wynik.pomocnik)
        powiedz("/usr/local/bin/change-boot", wynik.polecenie)

        print("")
        print(t("Your settings and the event log are left alone. Remove them by hand if you want:"))
        for sciezka in Odinstalowanie.coZostaje { print("  \(sciezka)") }
        print("")
        print(t("Now you can move Change-Boot to the Trash."))

        return wynik.wszystkoPoszlo ? .ok : .blad
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

    /// Ekran powitalny: gdzie jesteś, dokąd się da przejść i czym.
    ///
    /// Każdy dysk dostaje **gotowe do wklejenia polecenie**, bo o to chodziło
    /// w zgłoszeniu: człowiek ma zobaczyć swoje dyski i wiedzieć, co wpisać,
    /// a nie składać polecenie z opisu składni.
    ///
    /// Nazwy w cudzysłowie prostym — nazwa woluminu bywa ze spacją („Mac Lab")
    /// i wklejona bez cudzysłowu rozpadłaby się na dwa argumenty.
    static func powitanie() -> Kod {
        let konfiguracja = Configuration()
        let wykryte = SystemScanner.scan()
        let biezacy = SystemScanner.current()

        print("Change-Boot \(AppVersion.short) — " + t("startup system switcher"))
        print("")
        if let biezacy {
            print(t("Running from “\(biezacy.name)”  (macOS \(biezacy.productVersion) · \(biezacy.deviceIdentifier))"))
            print("")
        }

        guard !konfiguracja.entries.isEmpty else {
            print(t("No system is on the list yet."))
            print(t("Open the app window and add systems, or type:  change-boot help"))
            return .ok
        }

        print(t("YOUR SYSTEMS"))
        for wpis in konfiguracja.entries {
            let system = wykryte.first { $0.volumeUUID == wpis.volumeUUID }
            let nazwa = system?.name ?? wpis.lastKnownName
            let wyrownana = nazwa.padding(toLength: max(22, nazwa.count),
                                          withPad: " ", startingAt: 0)
            guard let system else {
                print("  ✕ \(wyrownana)  " + t("not connected"))
                continue
            }
            if system.volumeUUID == biezacy?.volumeUUID {
                print("  ● \(wyrownana)  " + t("← you are here"))
            } else {
                print("  ○ \(wyrownana)  change-boot switch '\(nazwa)' --restart")
            }
        }

        print("")
        print(t("Every command and exit code:  change-boot help"))
        return .ok
    }

    /// Pełny opis. Ludzie czytają to jak dokumentację, więc idzie przez katalog
    /// ciągów jak każdy inny napis — ale w kawałkach, a nie jednym blokiem:
    /// jeden wielki klucz z całym ekranem rozjeżdża się przy pierwszej zmianie
    /// i nie da się go przetłumaczyć bez przepisania całości.
    private static func pomoc() {
        print("Change-Boot \(AppVersion.short) — " + t("startup system switcher"))
        print("")
        print(t("USAGE"))
        print("  change-boot <" + t("command") + "> [" + t("options") + "]")
        print("")
        print(t("COMMANDS"))
        wiersz("list",                  t("configured systems and whether they are connected"))
        wiersz("current",               t("the system you are running from, and the firmware target"))
        wiersz("switch <" + t("name|UUID") + ">", t("sets the startup disk"))
        wiersz("eject <" + t("name|UUID") + ">",  t("ejects the WHOLE disk, not just the volume"))
        wiersz("volumes",               t("every mounted volume, its media and what is worth knowing"))
        wiersz("log",                   t("recent events"))
        wiersz("uninstall",             t("removes the helper, the command and the login item"))
        wiersz("help",                  t("this description"))
        wiersz("(" + t("no command") + ")", t("a full-screen view you can steer with the arrow keys"))
        print("")
        print(t("OPTIONS"))
        wiersz("--json",                t("machine-readable output"))
        wiersz("--csv",                 t("spreadsheet output — volumes only"))
        wiersz("--all",                 t("with volumes — also the APFS system plumbing"))
        wiersz("--plain",               t("plain text instead of the full-screen view"))
        wiersz("--restart",             t("restart once the startup disk is set"))
        wiersz("--clean / --no-clean",  t("clean start; without it the app setting decides"))
        wiersz("--limit <n>",           t("how many events to print (default 20)"))
        wiersz("--dry-run",             t("say what would happen and change nothing"))
        print("")
        print(t("EXIT CODES"))
        print("  " + t("0 ok · 1 error · 2 bad usage · 3 no such volume"))
        print("  " + t("4 the firmware did not accept the target · 5 cancelled"))
        print("")
        print(t("NOTE"))
        print("  " + t("Without the helper installed, every switch asks for an administrator"))
        print("  " + t("password in a system dialog — also when the command comes from"))
        print("  " + t("Terminal. The helper is installed in the app's Options."))
    }

    /// Jeden wiersz opisu polecenia: nazwa wyrównana do kolumny, potem opis.
    /// Wyrównanie liczone, a nie wklepane spacjami — tłumaczenie zmienia długości.
    private static func wiersz(_ nazwa: String, _ opis: String) {
        let szerokosc = 22
        let dopelnienie = nazwa.count < szerokosc
            ? String(repeating: " ", count: szerokosc - nazwa.count)
            : " "
        print("  \(nazwa)\(dopelnienie)\(opis)")
    }
}
