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
    }

    enum Skutek: String, Codable {
        case udane
        case nieudane
        case anulowane
    }

    enum Zrodlo: String, Codable {
        case okno
        case wierszPolecen
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

    static func zapisz(_ czynnosc: Czynnosc,
                       skutek: Skutek,
                       z: BootSystem? = nil,
                       na: BootSystem? = nil,
                       naNazwa: String? = nil,
                       naUUID: String? = nil,
                       czystyStart: Bool? = nil,
                       zrodlo: Zrodlo,
                       szczegol: String? = nil) {
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
            wersja: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            szczegol: szczegol)

        guard var dane = try? koder.encode(wpis) else { return }
        dane.append(0x0A)   // znak nowej linii

        let menedzer = FileManager.default
        try? menedzer.createDirectory(at: katalog, withIntermediateDirectories: true)
        przewinJesliTrzeba()

        if let uchwyt = try? FileHandle(forWritingTo: plik) {
            // `O_APPEND` na uchwycie otwartym do zapisu: `seekToEnd` plus `write`
            // wystarcza, bo wpisy są małe i idą jednym wywołaniem.
            defer { try? uchwyt.close() }
            _ = try? uchwyt.seekToEnd()
            try? uchwyt.write(contentsOf: dane)
        } else {
            try? dane.write(to: plik, options: .atomic)
        }
    }

    private static func przewinJesliTrzeba() {
        guard let atrybuty = try? FileManager.default.attributesOfItem(atPath: plik.path),
              let rozmiar = atrybuty[.size] as? Int, rozmiar > limitBajtow else { return }
        let poprzedni = katalog.appendingPathComponent("zdarzenia-poprzednie.jsonl")
        try? FileManager.default.removeItem(at: poprzedni)
        try? FileManager.default.moveItem(at: plik, to: poprzedni)
    }

    // MARK: - Odczyt

    /// Najnowsze zdarzenia, od najświeższego. Linie nie do odczytania są pomijane,
    /// a nie przerywają wczytywania — jedno uszkodzone zdarzenie nie może zabrać
    /// dostępu do reszty dziennika.
    static func ostatnie(_ ile: Int = 50) -> [Entry] {
        guard let tekst = try? String(contentsOf: plik, encoding: .utf8) else { return [] }
        return tekst
            .split(separator: "\n")
            .reversed()
            .prefix(ile * 2)
            .compactMap { linia -> Entry? in
                guard let dane = linia.data(using: .utf8) else { return nil }
                return try? dekoder.decode(Entry.self, from: dane)
            }
            .prefix(ile)
            .map { $0 }
    }
}
