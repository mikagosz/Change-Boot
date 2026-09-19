import Foundation

/// Zapis zdarzeń — co program zrobił, kiedy i z jakim skutkiem.
///
/// Po co: przełączenie dysku startowego jest zmianą, której skutek widać dopiero
/// po restarcie. Gdy coś pójdzie nie tak, jedynym świadkiem jest pamięć człowieka.
/// Serwis i pracownia potrzebują tego samego z innego powodu — chcą wiedzieć, kto
/// przestawił maszynę.
///
/// Format: **JSON Lines** w `~/Library/Application Support/Change-Boot/`. Jedna
/// linia na zdarzenie, dopisywana na koniec. Wybrany świadomie zamiast jednego
/// dużego JSON-a: dopisanie linii nie wymaga wczytania i przepisania całości, więc
/// wiersz poleceń i okno programu mogą pisać jednocześnie, nie kasując sobie wzajem
/// zapisów. Uszkodzenie ogona pliku kosztuje jedno zdarzenie, nie cały dziennik.
enum EventLog {

    struct Entry: Codable {
        let czas: Date
        let czynnosc: Czynnosc
        let skutek: Skutek
        /// Nazwa systemu, z którego maszyna pracowała w chwili zdarzenia.
        let zSystemu: String?
        let zUUID: String?
        /// Cel czynności — dla przełączenia i wysunięcia.
        let naSystem: String?
        let naUUID: String?
        let czystyStart: Bool?
        /// Skąd przyszło polecenie: okno programu czy wiersz poleceń.
        let zrodlo: Zrodlo
        let uzytkownik: String
        let wersja: String
        /// Treść błędu albo wyjście polecenia — tylko gdy jest czym uzupełnić.
        let szczegol: String?
    }

    enum Czynnosc: String, Codable {
        case przelaczenie
        case wysuniecie
        case instalacjaPomocnika
        case usunieciePomocnika
        case instalacjaPolecenia
        case usunieciePolecenia
        /// Wpis logowania założony przed przełączeniem, żeby program otworzył się
        /// sam po powrocie na ten system.
        case uzbrojenieNaPowrot
    }

    enum Skutek: String, Codable {
        case udane
        case nieudane
        case anulowane
        /// Czynność przyjęta, ale niedokończona — czeka na człowieka.
        /// Dziś jeden przypadek: pomocnik zarejestrowany i czekający na zgodę
        /// w Ustawieniach systemowych. Do 0.2.2 zapisywał się jako `nieudane`.
        case oczekuje
    }

    enum Zrodlo: String, Codable {
        case okno
        case wierszPolecen
    }

    /// Dlaczego zapis się nie udał.
    ///
    /// 🔴 Istnieje, bo do 0.2.5 `zapisz` zwracał `Void`, a każdą awarię połykało
    /// `try?` — trzynaście sztuk w jednym pliku. Przy katalogu bez prawa zapisu
    /// program nie mówił nic, a Opcje pokazywały „Nic się jeszcze nie wydarzyło".
    /// Znalezisko P1-04 z audytu 2026-09-19.
    enum Awaria: LocalizedError {
        case katalog(String)
        case zapis(String)

        var errorDescription: String? {
            switch self {
            case .katalog(let powod):
                return String(localized: "Could not create the log folder.\n\n\(powod)")
            case .zapis(let powod):
                return String(localized: "Could not write to the event log.\n\n\(powod)")
            }
        }
    }

    /// Co naprawdę zastano w dzienniku.
    ///
    /// Trzy przypadki, nie dwa — bo „pusto" i „nie dało się przeczytać" wyglądały
    /// do 0.2.5 identycznie i okno mówiło o obu to samo nieprawdziwe zdanie.
    enum Odczyt {
        case wpisy([Entry])
        /// Dziennika jeszcze nie ma — nic się nie wydarzyło. To jedyny przypadek,
        /// w którym wolno powiedzieć użytkownikowi „nic się nie wydarzyło".
        case pusty
        case nieczytelny(String)
    }

    // MARK: - Miejsce

    /// Podstawiany przez sprawdziany, żeby nie pisały po prawdziwym dzienniku
    /// użytkownika. W programie zostaje `nil` i nikt go nie rusza.
    static var katalogZastepczy: URL?

    /// Katalog programu w `Application Support`. Zakładany przy pierwszym zapisie.
    static var katalog: URL {
        if let katalogZastepczy { return katalogZastepczy }
        let bazowy = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return bazowy.appendingPathComponent("Change-Boot", isDirectory: true)
    }

    static var plik: URL { katalog.appendingPathComponent("zdarzenia.jsonl") }

    /// Powyżej tego rozmiaru dziennik jest przewijany do `zdarzenia-poprzednie.jsonl`.
    /// Jeden wpis to około 300 bajtów, więc to jakieś trzy tysiące zdarzeń — więcej,
    /// niż ktokolwiek przełączy dysk przez lata, a plik nie rośnie bez końca.
    private static let limitBajtow = 1_000_000

    // MARK: - Zapis

    private static let koder: JSONEncoder = {
        let k = JSONEncoder()
        k.dateEncodingStrategy = .iso8601
        k.outputFormatting = [.sortedKeys]
        return k
    }()

    private static let dekoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Ostatnia awaria zapisu, jeśli była.
    ///
    /// Czytana przez okno, żeby powiedzieć o niej **spokojnie, w sekcji Historia** —
    /// a nie oknem dialogowym. Zapis dziennika leci między innymi tuż przed
    /// restartem maszyny i nowa droga błędu nie ma prawa tam niczego zatrzymać.
    private(set) static var ostatniaAwaria: Awaria?

    /// Plik blokady. Osobny od dziennika, żeby blokada trzymała także przewijanie,
    /// czyli chwilę, w której dziennik zmienia i-węzeł.
    private static var zamek: URL { katalog.appendingPathComponent(".zamek") }

    /// Wykonuje `blok` pod wyłączną blokadą międzyprocesową.
    ///
    /// Gdy blokady nie da się założyć, robota idzie mimo to: dziennik bez blokady
    /// jest gorszy niż z blokadą, ale wciąż lepszy niż brak dziennika.
    private static func zBlokada<T>(_ blok: () -> T) -> T {
        let fd = open(zamek.path, O_WRONLY | O_CREAT, 0o600)
        guard fd >= 0 else { return blok() }
        defer { flock(fd, LOCK_UN); close(fd) }
        flock(fd, LOCK_EX)
        return blok()
    }

    /// Dopisuje zdarzenie. Zwraca `nil`, gdy poszło, albo powód niepowodzenia.
    ///
    /// 🔴 Zapis idzie przez `O_APPEND`, nie przez `seekToEnd()` + `write()`.
    /// Do 0.2.5 stał tu `FileHandle(forWritingTo:)` z komentarzem twierdzącym,
    /// że niesie `O_APPEND` — nie niósł. Bez tego znacznika przesunięcie i zapis
    /// to dwa osobne kroki: dwóch piszących odczytuje ten sam koniec pliku i obaj
    /// piszą pod to samo miejsce. Zmierzone 2026-09-19: osiem piszących naraz,
    /// **ginęło 137 z 480 wpisów**. Z `O_APPEND` jądro robi jedno i drugie
    /// niepodzielnie. Znalezisko P1-03 z audytu.
    @discardableResult
    static func zapisz(_ czynnosc: Czynnosc,
                       skutek: Skutek,
                       z: BootSystem? = nil,
                       na: BootSystem? = nil,
                       naNazwa: String? = nil,
                       naUUID: String? = nil,
                       czystyStart: Bool? = nil,
                       zrodlo: Zrodlo,
                       szczegol: String? = nil) -> Awaria? {
        let wpis = Entry(
            czas: Date(),
            czynnosc: czynnosc,
            skutek: skutek,
            zSystemu: z?.name,
            zUUID: z?.volumeUUID,
            naSystem: na?.name ?? naNazwa,
            naUUID: na?.volumeUUID ?? naUUID,
            czystyStart: czystyStart,
            zrodlo: zrodlo,
            uzytkownik: NSUserName(),
            wersja: AppBundle.wersja ?? "?",
            szczegol: szczegol)

        func zapamietaj(_ awaria: Awaria?) -> Awaria? {
            ostatniaAwaria = awaria
            return awaria
        }

        guard var dane = try? koder.encode(wpis) else {
            return zapamietaj(.zapis(String(localized: "The event could not be encoded.")))
        }
        dane.append(0x0A)   // znak nowej linii

        do {
            try FileManager.default.createDirectory(at: katalog, withIntermediateDirectories: true)
        } catch {
            return zapamietaj(.katalog(error.localizedDescription))
        }

        return zapamietaj(zBlokada {
            przewinJesliTrzeba()

            let fd = open(plik.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
            guard fd >= 0 else { return Awaria.zapis(String(cString: strerror(errno))) }
            defer { close(fd) }

            let zapisane = dane.withUnsafeBytes { bufor -> Int in
                write(fd, bufor.baseAddress, bufor.count)
            }
            guard zapisane == dane.count else {
                return Awaria.zapis(zapisane < 0
                    ? String(cString: strerror(errno))
                    : String(localized: "Only part of the entry was written."))
            }
            return nil
        })
    }

    private static func przewinJesliTrzeba() {
        guard let atrybuty = try? FileManager.default.attributesOfItem(atPath: plik.path),
              let rozmiar = atrybuty[.size] as? Int, rozmiar > limitBajtow else { return }
        let poprzedni = katalog.appendingPathComponent("zdarzenia-poprzednie.jsonl")
        try? FileManager.default.removeItem(at: poprzedni)
        try? FileManager.default.moveItem(at: plik, to: poprzedni)
    }

    // MARK: - Odczyt

    /// Najnowsze zdarzenia z rozróżnieniem „pusto" od „nie dało się przeczytać".
    ///
    /// Linie nie do odczytania są pomijane, a nie przerywają wczytywania — jedno
    /// uszkodzone zdarzenie nie może zabrać dostępu do reszty dziennika. Ale brak
    /// prawa odczytu do **pliku** to co innego niż pusty dziennik i program ma
    /// o tym powiedzieć, zamiast twierdzić, że nic się nie wydarzyło (P1-04).
    static func przeczytaj(_ ile: Int = 50) -> Odczyt {
        guard FileManager.default.fileExists(atPath: plik.path) else { return .pusty }
        let tekst: String
        do {
            tekst = try String(contentsOf: plik, encoding: .utf8)
        } catch {
            return .nieczytelny(error.localizedDescription)
        }
        let wpisy = tekst
            .split(separator: "\n")
            .reversed()
            .prefix(ile * 2)
            .compactMap { linia -> Entry? in
                guard let dane = linia.data(using: .utf8) else { return nil }
                return try? dekoder.decode(Entry.self, from: dane)
            }
            .prefix(ile)
            .map { $0 }
        return wpisy.isEmpty ? .pusty : .wpisy(wpisy)
    }

    /// Wygodny skrót dla miejsc, którym wystarczy lista — sprawdziany i `log`
    /// w wierszu poleceń. Nie odróżnia pustego dziennika od nieczytelnego;
    /// tam, gdzie to rozróżnienie ma znaczenie, woła się `przeczytaj`.
    static func ostatnie(_ ile: Int = 50) -> [Entry] {
        if case .wpisy(let w) = przeczytaj(ile) { return w }
        return []
    }
}
