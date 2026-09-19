import Foundation

/// Przegląd woluminów i kondycji nośników.
///
/// Po co osobno od `SystemScanner`: tamten szuka **systemów startowych** i zna
/// tylko te. Pracownia chce wiedzieć, co w ogóle jest podpięte do maszyny, ile
/// na tym zostało miejsca i czy nośnik nie umiera — także o woluminach, z których
/// nikt nigdy nie wystartuje.
///
/// 🔴 Ten moduł **niczego nie ocenia w skali**. Żadnych „kondycja 87%", żadnych
/// zielonych kropek liczonych z niczego. Oddaje to, co zmierzone, i osobno listę
/// uwag, z których każda ma próg zapisany wprost w kodzie. Ocena wymyślona przez
/// program byłaby liczbą, której nikt nie umie obronić przed klientem.
enum Kondycja {

    // MARK: - Kształt odpowiedzi

    /// Nośnik fizyczny, na którym leży wolumin.
    struct Nosnik: Encodable {
        let urzadzenie: String
        /// Nazwa handlowa z kontrolera, np. `APPLE SSD AP0256Z`. Bywa pusta —
        /// obudowy USB często nie podają niczego sensownego.
        let nazwa: String?
        /// `USB`, `Apple Fabric`, `Thunderbolt`, `SATA`…
        let magistrala: String?
        let ssd: Bool?
        let pojemnosc: Int64?
        /// 🔴 Oddawane **dosłownie**, jak mówi `diskutil`: `Verified`,
        /// `Not Supported`, `Failing`. Zmierzone 2026-09-19: wewnętrzny SSD Apple
        /// oddaje `Verified`, ta sama obudowa USB `Not Supported`. Zamiana
        /// „Not Supported" na cokolwiek innego byłaby zmyślaniem — most USB po
        /// prostu nie przekazuje SMART-a i nie znaczy to nic o stanie dysku.
        let smart: String?
    }

    struct Wolumin: Encodable {
        let nazwa: String
        let uuid: String?
        let punktMontowania: String
        let urzadzenie: String?
        let systemPlikow: String?
        let wewnetrzny: Bool?
        /// Udział sieciowy — nie ma nośnika, nie ma SMART-a, nie da się z niego
        /// wystartować. Osobne pole, bo bez niego taki wolumin wygląda w raporcie
        /// jak dysk, o którym program nic nie wie.
        let sieciowy: Bool
        let wysuwalny: Bool?
        let szyfrowany: Bool?
        let zapisywalny: Bool?
        let startowy: Bool?
        /// Pojemność woluminu w bajtach.
        let pojemnosc: Int64?
        /// Wolne miejsce liczone tak, jak pokazuje je Finder — z tym, co system
        /// może zwolnić. To jest liczba, którą człowiek widzi w oknie.
        let wolne: Int64?
        /// 🔴 Wolne miejsce w KONTENERZE APFS. Osobne pole, bo to inna liczba
        /// i inne pytanie. Zmierzone 2026-09-19 na `/`: `FreeSpace` z `diskutil`
        /// pokazuje **0**, bo wolumin APFS nie ma własnej puli — miejsce jest
        /// wspólne dla całego kontenera (`APFSContainerFree` = 74 645 540 864).
        /// Raport pokazujący tu zero wyglądałby na dysk pełny w 100%.
        let wolneWKontenerze: Int64?
        let nosnik: Nosnik?
        /// Uwagi z progami zapisanymi w kodzie — patrz `uwagi(dla:)`.
        /// `var`, bo powstają z już policzonych pól tego samego opisu.
        var uwagi: [String] = []
    }

    // MARK: - Progi

    /// Poniżej tylu procent wolnego miejsca wolumin dostaje uwagę.
    ///
    /// Dziesięć procent, bo poniżej tego APFS zaczyna odmawiać migawek, a
    /// aktualizacja systemu nie ma gdzie rozpakować obrazu. Próg stoi **tutaj**,
    /// jedną stałą, a nie rozsypany po trzech miejscach z trzema wartościami.
    static let progWolnego = 0.10

    // MARK: - Przegląd

    /// Wszystkie zamontowane woluminy, w kolejności, jaką oddaje system.
    ///
    /// Enumeracja idzie **bez** `.skipHiddenVolumes` — ta opcja gubi woluminy
    /// montowane z `nobrowse`, w tym wolumin danych instalacji systemu. Na tej
    /// samej ślepocie stoi Finder; przegląd, który nie widzi połowy woluminów,
    /// nie jest przeglądem.
    static func przeglad(wszystkie: Bool = false) -> [Wolumin] {
        let punkty = (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: []) ?? []).map(\.path)
        let wybrane = wszystkie ? punkty : punkty.filter(czyWidocznyDlaCzlowieka)
        return wybrane.map { opisz($0) }
    }

    /// Czy to wolumin, o którym człowiek myśli „dysk", czy hydraulika APFS-a.
    ///
    /// 🔴 Pierwsza wersja `volumes` wypisywała wszystko: `VM`, `Preboot`,
    /// `Update`, `xART`, `iSCPreboot`, `Hardware`. Osiem wierszy hydrauliki na
    /// dwa prawdziwe dyski — raport, w którym trzeba szukać treści, jest gorszy
    /// niż jego brak. Reszta jest pod `--all`, bo przy diagnozowaniu bywa
    /// potrzebna.
    ///
    /// Sito po punkcie montowania, nie po roli APFS: rola wymaga osobnego
    /// `diskutil apfs list` i drugiego przebiegu parsowania, a punkt montowania
    /// stoi już w odczytanym słowniku. `/System/Volumes/` to z definicji miejsce
    /// systemowej hydrauliki, a `Recovery` jest pod `/Volumes/`, ale nikt go nie
    /// traktuje jak dysku do pracy.
    static func czyWidocznyDlaCzlowieka(_ punkt: String) -> Bool {
        if punkt == "/" { return true }
        if punkt.hasPrefix("/System/Volumes/") { return false }
        if punkt == "/Volumes/Recovery" { return false }
        return punkt.hasPrefix("/Volumes/")
    }

    static func opisz(_ punkt: String) -> Wolumin {
        let dane = DiskUtility.info(punkt)
        let urzadzenie = dane?["DeviceIdentifier"] as? String
        let nosnikId = DiskUtility.wholeDisk(forVolumeAt: punkt)

        let zasoby = zasoby(punkt)
        let pojemnosc = liczba(dane?["TotalSize"]) ?? zasoby.pojemnosc
        let wolneKontener = liczba(dane?["APFSContainerFree"])

        var wolumin = Wolumin(
            nazwa: dane?["VolumeName"] as? String
                ?? URL(fileURLWithPath: punkt).lastPathComponent,
            uuid: dane?["VolumeUUID"] as? String,
            punktMontowania: punkt,
            urzadzenie: urzadzenie,
            systemPlikow: dane?["FilesystemName"] as? String,
            wewnetrzny: dane?["Internal"] as? Bool,
            sieciowy: zasoby.sieciowy,
            wysuwalny: dane?["Ejectable"] as? Bool,
            szyfrowany: dane?["Encryption"] as? Bool,
            zapisywalny: zasoby.zapisywalny ?? (dane?["WritableVolume"] as? Bool),
            startowy: dane?["Bootable"] as? Bool,
            pojemnosc: pojemnosc,
            wolne: zasoby.wolne,
            wolneWKontenerze: wolneKontener,
            nosnik: nosnikId.map { opiszNosnik($0) })

        wolumin.uwagi = uwagi(dla: wolumin)
        return wolumin
    }

    private static func opiszNosnik(_ identyfikator: String) -> Nosnik {
        let dane = DiskUtility.info(identyfikator)
        let nazwa = dane?["MediaName"] as? String
        return Nosnik(urzadzenie: identyfikator,
                      nazwa: (nazwa?.isEmpty ?? true) ? nil : nazwa,
                      magistrala: dane?["BusProtocol"] as? String,
                      ssd: dane?["SolidState"] as? Bool,
                      pojemnosc: liczba(dane?["TotalSize"]),
                      smart: dane?["SMARTStatus"] as? String)
    }

    /// To, co o woluminie wie Foundation — i wie **więcej** niż `diskutil`.
    ///
    /// 🔴 Zmierzone 2026-09-19 na czterech woluminach naraz:
    ///
    ///     wolumin              important   available     diskutil
    ///     /                    96,48 GB    74,63 GB      TotalSize ✓
    ///     /Volumes/Serwer      0           268,36 GB     nic (udział SMB)
    ///     /Volumes/Mac Lab     0           460,31 GB     FreeSpace 0
    ///     /Volumes/Mac Lab-Data 461,31 GB  460,31 GB     TotalSize ✓
    ///
    /// Stąd dwie decyzje. `volumeAvailableCapacityForImportantUsage` jest liczbą
    /// Findera i tę pokazujemy, **gdy jest** — ale dla udziału sieciowego i dla
    /// zapieczętowanego woluminu systemowego oddaje zero, więc zero znaczy tu
    /// „nie wiem" i schodzimy na zwykłe `volumeAvailableCapacity`.
    /// Bez tego raport pokazywał „? wolne" przy udziałach i „zero KB" przy
    /// `Mac Lab` — obie liczby nieprawdziwe.
    ///
    /// `volumeIsLocal` jest jedynym źródłem, które odróżnia udział sieciowy:
    /// `diskutil` o nim nie wie w ogóle i oddaje pusty słownik.
    private static func zasoby(_ punkt: String) -> (pojemnosc: Int64?, wolne: Int64?,
                                                    sieciowy: Bool, zapisywalny: Bool?) {
        let klucze: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey, .volumeIsReadOnlyKey,
        ]
        guard let w = try? URL(fileURLWithPath: punkt).resourceValues(forKeys: klucze) else {
            return (nil, nil, false, nil)
        }
        let wazne = w.volumeAvailableCapacityForImportantUsage
        let zwykle = w.volumeAvailableCapacity.map(Int64.init)
        return (w.volumeTotalCapacity.map(Int64.init),
                (wazne ?? 0) > 0 ? wazne : zwykle,
                w.volumeIsLocal == false,
                w.volumeIsReadOnly.map { !$0 })
    }

    private static func liczba(_ wartosc: Any?) -> Int64? {
        (wartosc as? NSNumber)?.int64Value
    }

    // MARK: - Uwagi

    /// Uwagi o woluminie. Każda ma próg albo wartość zmierzoną — żadna nie jest
    /// przeczuciem. Pusta lista znaczy „nic mi nie wyszło", a nie „jest dobrze":
    /// SMART-a przez most USB nie widać i uczciwiej tego nie udawać.
    static func uwagi(dla wolumin: Wolumin) -> [String] {
        var lista: [String] = []

        if let smart = wolumin.nosnik?.smart,
           smart != "Verified", smart != "Not Supported" {
            lista.append(CommandLineTool.t("SMART reports: \(smart)"))
        }

        if let udzial = udzialWolnego(wolumin), udzial < progWolnego {
            lista.append(CommandLineTool.t("Only \(Int((udzial * 100).rounded()))% free"))
        }

        return lista
    }

    /// Ile wolnego miejsca zostało, jako ułamek pojemności — albo `nil`, gdy
    /// się tego nie da powiedzieć.
    ///
    /// 🔴 `nil` jest tu odpowiedzią, nie porażką. Pierwsza wersja liczyła sam
    /// `wolne` i dla woluminów systemowych dostawała zero, bo
    /// `volumeAvailableCapacityForImportantUsage` ich nie raportuje. Skutek:
    /// przy każdym uruchomieniu cztery ostrzeżenia „Mniej niż 0% wolnego"
    /// o woluminach, którym nic nie jest. **Ostrzeżenie o czymś, czego nie
    /// zmierzono, jest gorsze niż jego brak** — uczy patrzącego, żeby
    /// ostrzeżenia ignorować.
    ///
    /// Zero z `wolne` znaczy więc „nie wiem" i schodzimy na miejsce w kontenerze
    /// APFS, które dla woluminu systemowego jest liczbą prawdziwą.
    static func udzialWolnego(_ wolumin: Wolumin) -> Double? {
        guard let pojemnosc = wolumin.pojemnosc, pojemnosc > 0 else { return nil }
        let wolne = (wolumin.wolne ?? 0) > 0 ? wolumin.wolne : wolumin.wolneWKontenerze
        guard let wolne, wolne > 0 else { return nil }
        return Double(wolne) / Double(pojemnosc)
    }

    // MARK: - Eksport

    /// Przegląd jako CSV — jeden wiersz na wolumin, przecinek jako rozdzielnik.
    ///
    /// 🔴 Cudzysłowy i przecinki w nazwie woluminu są tu prawdziwym przypadkiem,
    /// nie teoretycznym: macOS pozwala na oba znaki w nazwie dysku. Bez cytowania
    /// jeden dysk nazwany „Backup, stary" rozsypuje cały plik o jedną kolumnę
    /// i widać to dopiero w arkuszu.
    static func csv(_ woluminy: [Wolumin]) -> String {
        let naglowki = ["nazwa", "uuid", "punkt_montowania", "urzadzenie",
                        "system_plikow", "wewnetrzny", "sieciowy", "szyfrowany", "startowy",
                        "pojemnosc_b", "wolne_b", "nosnik", "nosnik_nazwa",
                        "magistrala", "ssd", "smart", "uwagi"]
        var wiersze = [naglowki.joined(separator: ",")]

        for w in woluminy {
            let pola: [String] = [
                w.nazwa,
                w.uuid ?? "",
                w.punktMontowania,
                w.urzadzenie ?? "",
                w.systemPlikow ?? "",
                logiczna(w.wewnetrzny),
                logiczna(w.sieciowy),
                logiczna(w.szyfrowany),
                logiczna(w.startowy),
                w.pojemnosc.map(String.init) ?? "",
                w.wolne.map(String.init) ?? "",
                w.nosnik?.urzadzenie ?? "",
                w.nosnik?.nazwa ?? "",
                w.nosnik?.magistrala ?? "",
                logiczna(w.nosnik?.ssd),
                w.nosnik?.smart ?? "",
                w.uwagi.joined(separator: "; "),
            ]
            wiersze.append(pola.map(cytuj).joined(separator: ","))
        }
        return wiersze.joined(separator: "\n")
    }

    private static func logiczna(_ wartosc: Bool?) -> String {
        guard let wartosc else { return "" }
        return wartosc ? "tak" : "nie"
    }

    /// Cytowanie wg RFC 4180: pole w cudzysłowach, a cudzysłów w środku podwojony.
    static func cytuj(_ pole: String) -> String {
        guard pole.contains(",") || pole.contains("\"") || pole.contains("\n") else {
            return pole
        }
        return "\"" + pole.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
