import Foundation

/// Nazwy i wymagania wspólne dla obu stron mostu: programu i pomocnika.
///
/// Siedzą w jednym miejscu świadomie — rozjazd nazwy usługi Macha między
/// programem a plistem demona nie daje żadnego błędu kompilacji, tylko cichy
/// brak połączenia w czasie działania.
enum HelperNames {
    /// Etykieta demona. **Musi** być identyczna z nazwą pliku plist w
    /// `Contents/Library/LaunchDaemons/` — `SMAppService` szuka po nazwie pliku,
    /// a launchd sprawdza zgodność z kluczem `Label`.
    static let label = "com.mikagosz.ChangeBoot.Helper"

    /// Plik plist w bundlu programu, tak jak widzi go `SMAppService.daemon(plistName:)`.
    static let plistName = "com.mikagosz.ChangeBoot.Helper.plist"

    /// Usługa Macha, przez którą program rozmawia z pomocnikiem.
    static let machService = "com.mikagosz.ChangeBoot.Helper"

    /// Argument przełączający tę samą binarkę w tryb demona — patrz `main.swift`.
    static let daemonArgument = "--helper"

    /// Czy ten wektor argumentów to wywołanie demona przez launchd.
    ///
    /// 🔴 Rozstrzyga **kształt całego wektora**, nie to, czy `--helper` gdzieś
    /// w nim stoi. Do 0.2.8 było tu `arguments.contains(daemonArgument)` i rola
    /// demona wygrywała z każdym czasownikiem: `change-boot list --helper`
    /// wchodziło w `RunLoop.current.run()` i wisiało w nieskończoność, bez jednego
    /// znaku na wyjściu. Zmierzone 2026-09-19, ubite dopiero SIGKILL-em po ośmiu
    /// sekundach (P1-07 z audytu).
    ///
    /// launchd podaje dokładnie to, co stoi w `ProgramArguments` plistu:
    /// `["Contents/MacOS/Change-Boot", "--helper"]`. Jeden argument, ani więcej,
    /// ani mniej — i tylko to przepuszczamy.
    static func czyWywolanieDemona(_ argumenty: [String]) -> Bool {
        Array(argumenty.dropFirst()) == [daemonArgument]
    }
}

/// Kto ma prawo rozmawiać z pomocnikiem i czyjego pomocnika słucha program.
///
/// 🔴 To jedyna bariera, jaka dzieli roota od dowolnego procesu na tej maszynie.
/// Bez niej każdy program użytkownika mógłby połączyć się z usługą Macha
/// i kazać przestawić dysk startowy.
///
/// Wymaganie odpowiada temu, co wypisuje `codesign -d -r-` na zbudowanym
/// programie. Certyfikat *Mikagosz Local Developer* nie ma Team ID (podpis lokalny,
/// `TeamIdentifier=not set`), więc tożsamość niesie odcisk certyfikatu liścia —
/// `anchor apple generic and certificate leaf[subject.OU]` nie ma tu czego złapać.
///
/// > Zmiana certyfikatu = zmiana tej stałej. Odcisk bierze się z
/// > `codesign -d -r- Change-Boot.app`, nie z `security find-identity -v`
/// > (ta opcja filtruje do zaufanych i lokalnego certyfikatu nie pokazuje).
enum HelperTrust {
    static let requirement = """
        identifier "com.mikagosz.ChangeBoot" \
        and certificate leaf = H"85c274e1928b36d546b36b8462a879e6a97bfc22"
        """
}

/// Wszystko, co pomocnik umie zrobić z uprawnieniami roota.
///
/// Celowo **wąskie**: jedna czynność o ustalonym kształcie, nie „uruchom polecenie".
/// Poprzednik (`do shell script … with administrator privileges`) brał dowolny
/// tekst; tutaj strona uprzywilejowana sama składa wywołanie `bless`, a z zewnątrz
/// przychodzi wyłącznie punkt montowania.
@objc protocol HelperProtocol {
    /// Ustawia dysk startowy na wolumin zamontowany w `mountPoint`.
    /// Odpowiedź: kod wyjścia `bless` i jego wyjście tekstowe.
    func setStartupDisk(mountPoint: String, reply: @escaping (Int32, String) -> Void)

    /// Wersja pomocnika. Służy do sprawdzenia, czy zarejestrowany demon nie jest
    /// starszy od programu, który się z nim łączy.
    func version(reply: @escaping (String) -> Void)
}
