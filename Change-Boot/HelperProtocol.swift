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
///
/// > [!danger] 🔴 Sam certyfikat to za mało — audyt SBW 2026-09-24, B-P1-01
/// > Do 0.2.20 wymaganie brzmiało „ten identyfikator i ten certyfikat”. Spełniała je
/// > każda stara paczka z `App zip/` (0.2.2 bez Hardened Runtime, z `get-task-allow`,
/// > czyli z drzwiami do wstrzyknięcia kodu), każdy build Debug i dowolny program,
/// > który ktoś tym certyfikatem podpisał. Dziś dochodzą dwa warunki:
/// > - **numer builda co najmniej `minimalnyBuild`** — wycina wszystkie wcześniejsze
/// >   wydania. Pomocnik jest tą samą binarką co program, więc aktualizacja programu
/// >   podnosi obie strony naraz;
/// > - **brak `get-task-allow`** — wycina buildy Debug.
/// >
/// > Program, który sam się podpisze certyfikatem i wpisze sobie wysoki numer, dalej
/// > przejdzie — przed tym chroni dopiero dostęp do klucza prywatnego (do decyzji właściciela projektu).
/// > Dlatego pomocnik sam sprawdza też politykę MDM (`HelperService.politykaPozwala`).
///
/// > ⚠️ `>=` w języku wymagań porównuje **liczby**, nie napisy — zmierzone 2026-09-24
/// > `codesign -v -R` na próbnych paczkach: próg 41 odrzuca 5, 9 i 40, przepuszcza 41,
/// > 100 i 400 (przy porównaniu napisów „9” i „5” by przeszły). `Testy/pomocnik`
/// > sprawdza wymaganie na zbudowanym programie. Podnosząc próg, podnoś go do builda,
/// > który ma wejść.
enum HelperTrust {
    /// Pierwszy build z tym wymaganiem (0.2.21). Nie podnosić bez potrzeby: każdy
    /// wyższy próg odcina od pomocnika wszystkie wcześniejsze kopie programu.
    static let minimalnyBuild = 41

    static let requirement = """
        identifier "com.mikagosz.ChangeBoot" \
        and certificate leaf = H"85c274e1928b36d546b36b8462a879e6a97bfc22" \
        and info["CFBundleVersion"] >= "\(minimalnyBuild)" \
        and !(entitlement["com.apple.security.get-task-allow"] exists)
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

    // 🔴 Nic więcej. Każda metoda tego protokołu jest czymś, co da się wywołać
    // na demonie roota, więc nieużywana metoda z niego wychodzi. `version()`
    // stało tu do 0.2.12 i nikt go nigdy nie zawołał (P2-14 z audytu).
}
