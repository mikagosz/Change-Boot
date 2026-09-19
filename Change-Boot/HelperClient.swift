import Foundation
import ServiceManagement

/// Strona programu: rejestracja pomocnika i rozmowa z nim po XPC.
///
/// Po co to w ogóle jest: bez pomocnika każde przełączenie dysku startowego
/// wywołuje systemowe okno hasła, bo `bless --setBoot` wymaga roota. Pomocnik
/// zarejestrowany przez `SMAppService` bierze zgodę **raz**, przy instalacji,
/// i od tej pory wykonuje tę jedną czynność bez pytania.
enum HelperClient {

    enum Failure: LocalizedError {
        case notInstalled
        case needsApproval
        /// Zarejestrowany, ale nie odpowiada — launchd go nie uruchamia.
        case milczy
        case connection(String)
        case bless(code: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return String(localized: "The privileged helper is not installed.")
            case .needsApproval:
                return String(localized: "The helper is waiting for your approval in System Settings → General → Login Items.")
            case .milczy:
                return String(localized: "The helper is registered but does not answer. Remove it in Options and install it again.")
            case .connection(let message):
                return String(localized: "Could not talk to the privileged helper.\n\n\(message)")
            case .bless(let code, let output):
                return String(localized: "bless failed (\(code)).\n\n\(output)")
            }
        }
    }

    private static var service: SMAppService {
        SMAppService.daemon(plistName: HelperNames.plistName)
    }

    // MARK: - Stan

    static var status: SMAppService.Status { service.status }

    /// Czy da się na pomocniku polegać w tej chwili.
    ///
    /// ⚠️ To jest odpowiedź **rejestru**, nie pomiar. Zmierzone 2026-09-19:
    /// `SMAppService` mówił `.enabled`, a launchd nie umiał demona uruchomić
    /// i wypisywał `service inactive` co dziesięć sekund. Rejestracja wskazywała
    /// wtedy na stary pakiet (`parent bundle version = 23` przy zainstalowanym 39).
    /// Jedynym dowodem na działającego pomocnika jest jego odpowiedź — dlatego
    /// `setStartupDisk` ma termin, a `BootActions` drogę zastępczą.
    static var isReady: Bool { service.status == .enabled }

    /// Stan opisany tak, żeby dało się go pokazać w oknie.
    static var statusDescription: String {
        switch service.status {
        case .enabled:          return String(localized: "Installed — no password needed to switch")
        case .requiresApproval: return String(localized: "Waiting for approval in System Settings")
        case .notRegistered:    return String(localized: "Not installed — macOS asks for your password on every switch")
        case .notFound:         return String(localized: "Not found in the app bundle")
        @unknown default:       return String(localized: "Unknown")
        }
    }

    /// Czy program stoi w miejscu, z którego nie warto rejestrować demona.
    ///
    /// `BundleProgram` w pliście jest ścieżką **względem bundla**, a launchd
    /// zapamiętuje położenie bundla z chwili rejestracji. Program zarejestrowany
    /// z `DerivedData` przestaje działać po pierwszym przebudowaniu — i wygląda
    /// to wtedy na usterkę pomocnika, a nie na przeniesiony plik.
    static var isInTemporaryLocation: Bool {
        let path = AppBundle.main.bundleURL.path
        return path.contains("/DerivedData/") || path.contains("/Volumes/")
    }

    // MARK: - Instalacja

    /// Czym skończyła się rejestracja pomocnika.
    ///
    /// Trzeci stan istnieje, bo macOS ma trzeci stan — patrz `install()`.
    enum Wynik {
        case gotowy
        case czekaNaZgode
    }

    /// Rejestruje demona. Przy pierwszym razie macOS pyta o zgodę administratora.
    ///
    /// 🔴 **`register()` rzuca także wtedy, gdy rejestracja się UDAŁA.** macOS
    /// pokazuje wtedy powiadomienie „Aktywność aplikacji w tle — «Change-Boot» może
    /// działać w tle u wszystkich użytkowników. Czy to zezwolić?", a wywołanie kończy
    /// się błędem `Operation not permitted`. Po kliknięciu „Zezwól" pomocnik jest
    /// zainstalowany i działa — tyle że program zdążył już zapisać porażkę.
    ///
    /// Zmierzone 2026-09-19 na dwóch systemach niezależnie; dowód w dzienniku
    /// zdarzeń obu instalacji:
    /// `{"czynnosc":"instalacjaPomocnika","skutek":"nieudane",`
    /// ` "szczegol":"Nie można ukończyć tej operacji. Operation not permitted"}`.
    /// Zgłoszone przez [U]: *„historia pokazuje błędnie, że instalacja pomocnika
    /// się nie udała"*.
    ///
    /// Dlatego o skutku orzeka **stan usługi po wywołaniu**, a nie to, czy rzuciło.
    /// `SMAppService` jest tu jedynym świadkiem, który mówi prawdę.
    ///
    /// Zarejestrowany demon wskazuje na **to** miejsce, w którym program stoi
    /// w chwili rejestracji: `BundleProgram` w pliście jest ścieżką względem bundla.
    /// Przeniesienie programu po rejestracji zrywa powiązanie i trzeba je odnowić.
    @discardableResult
    static func install() throws -> Wynik {
        zapomnijZywotnosc()
        do {
            try service.register()
        } catch {
            switch service.status {
            case .enabled:          return .gotowy
            case .requiresApproval: return .czekaNaZgode
            default:                throw error
            }
        }
        return service.status == .requiresApproval ? .czekaNaZgode : .gotowy
    }

    static func uninstall() throws {
        zapomnijZywotnosc()
        try service.unregister()
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Rozmowa

    /// Ustawia dysk startowy rękami pomocnika. Rzuca, gdy pomocnika nie ma —
    /// decyzję o drodze zastępczej podejmuje `BootActions`, nie ten typ.
    ///
    /// Dowód życia idzie **przed** właściwym wywołaniem i ma własny, krótki
    /// termin — patrz `czyOdpowiada()`. Bez niego pomocnik zarejestrowany,
    /// ale nieuruchamialny kosztował piętnaście sekund przy każdym kliknięciu.
    static func setStartupDisk(mountPoint: String) throws {
        switch service.status {
        case .enabled:          break
        case .requiresApproval: throw Failure.needsApproval
        default:                throw Failure.notInstalled
        }
        guard czyOdpowiada() else { throw Failure.milczy }
        try zawolaj(mountPoint: mountPoint, termin: terminOdpowiedzi)
    }

    /// Jedna rozmowa z pomocnikiem, z terminem podanym z zewnątrz.
    ///
    /// Termin jest parametrem, bo mierzymy tym dwie różne rzeczy: dowód życia
    /// (krótko — to jedno odbicie) i prawdziwe `bless` (hojnie — na Apple Silicon
    /// bywa powolne). Jedna stała nie może być dobra dla obu.
    private static func zawolaj(mountPoint: String, termin: TimeInterval) throws {
        let connection = NSXPCConnection(machServiceName: HelperNames.machService,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let zamek = NSLock()
        var connectionError: String?
        var code: Int32 = -1
        var output = ""
        let czekacz = DispatchSemaphore(value: 0)

        // 🔴 Proxy ASYNCHRONICZNE plus semafor z terminem, a NIE
        // `synchronousRemoteObjectProxyWithErrorHandler`.
        //
        // Proxy synchroniczne czeka **bez końca**, gdy launchd nie umie
        // uruchomić demona — a umie nie umieć. Zmierzone 2026-09-19 na maszynie
        // [U]: rejestracja wskazywała na stary pakiet (`parent bundle
        // version = 23` przy zainstalowanym 39), więc launchd co dziesięć sekund
        // wypisywał `service inactive: com.mikagosz.ChangeBoot.Helper` i nigdy
        // go nie wstał. Program — okno i widok terminalowy tak samo — wisiał
        // do ubicia procesu. 38 takich prób w jednym logu.
        //
        // `service.status` mówiło przy tym `.enabled`. **Rejestracja nie jest
        // dowodem na działającego demona** — dowodem jest odpowiedź.
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            zamek.lock()
            connectionError = error.localizedDescription
            zamek.unlock()
            czekacz.signal()
        } as? HelperProtocol

        guard let proxy else {
            throw Failure.connection(String(localized: "No proxy object."))
        }

        proxy.setStartupDisk(mountPoint: mountPoint) { odpowiedzKod, odpowiedzTekst in
            zamek.lock()
            code = odpowiedzKod
            output = odpowiedzTekst
            zamek.unlock()
            czekacz.signal()
        }

        // Termin jest hojny, bo `bless` na Apple Silicon bywa powolny, ale
        // SKOŃCZONY — bo program, który wisi, jest gorszy od programu, który
        // pyta o hasło. Po terminie `BootActions` schodzi na drogę zastępczą.
        guard czekacz.wait(timeout: .now() + termin) == .success else {
            throw Failure.connection(String(localized: "The helper did not answer within \(Int(termin)) s. It is registered but not starting."))
        }

        zamek.lock(); defer { zamek.unlock() }
        if let connectionError { throw Failure.connection(connectionError) }
        guard code == 0 else { throw Failure.bless(code: code, output: output) }
    }

    /// Ile czekamy na `bless` po drugiej stronie mostu. Hojnie, bo `bless`
    /// na Apple Silicon bywa powolny — ale SKOŃCZENIE.
    static let terminOdpowiedzi: TimeInterval = 15

    // MARK: - Dowód życia

    /// Ile czekamy na sam dowód życia. Krótko: to jedno odbicie po moście,
    /// bez żadnej roboty po drugiej stronie.
    static let terminZywotnosci: TimeInterval = 2

    private static let zamekZywotnosci = NSLock()
    private static var zywotnosc: Bool?

    /// Czy pomocnik naprawdę odpowiada.
    ///
    /// 🔴 To jest to, czego `isReady` powiedzieć nie umie. Na maszynie [U]
    /// `SMAppService` mówił `.enabled`, a launchd demona nie uruchamiał —
    /// i każde przełączenie kosztowało przez to **piętnaście sekund** czekania,
    /// zanim program zszedł na okno hasła. Zgłoszenie [U] 2026-09-20:
    /// *„po kliknięciu aby się przełączyć czeka się stanowczo za długo"*.
    ///
    /// Odpowiedź jest pamiętana do końca działania procesu. Rejestracja nie
    /// zmienia się sama, a płacenie dwóch sekund przy każdym kliknięciu byłoby
    /// tą samą wadą w mniejszej skali. Po instalacji i po usunięciu pomocnika
    /// pamięć kasuje `zapomnijZywotnosc()`.
    static func czyOdpowiada() -> Bool {
        zamekZywotnosci.lock()
        let znane = zywotnosc
        zamekZywotnosci.unlock()
        if let znane { return znane }

        let wynik = zmierzZywotnosc()

        zamekZywotnosci.lock()
        zywotnosc = wynik
        zamekZywotnosci.unlock()
        return wynik
    }

    /// Kasuje pamięć o dowodzie życia. Woła się po każdej zmianie rejestracji.
    static func zapomnijZywotnosc() {
        zamekZywotnosci.lock()
        zywotnosc = nil
        zamekZywotnosci.unlock()
    }

    /// Pyta o dowód życia **w tle**, żeby kliknięcie nie czekało na odpowiedź.
    ///
    /// Woła to okno przy starcie i widok pełnoekranowy przy wejściu. Zanim
    /// człowiek wybierze system i potwierdzi, odpowiedź zwykle już jest —
    /// a gdy nie, kosztuje najwyżej `terminZywotnosci`.
    static func sprawdzWTle() {
        DispatchQueue.global(qos: .utility).async { _ = czyOdpowiada() }
    }

    /// Jedno odbicie po moście, bez żadnego skutku po drugiej stronie.
    ///
    /// 🔴 Świadomie **nie** nową metodą protokołu, choć `ping()` byłoby
    /// czytelniejsze. Dwa powody, oba mocniejsze od czytelności:
    ///
    /// 1. Każda metoda tego protokołu jest czymś, co da się wywołać na demonie
    ///    roota — dlatego martwe `version()` z niego wyleciało (P2-14 z audytu).
    /// 2. Metoda dodana dziś nie istnieje w pomocniku **zainstalowanym wczoraj**,
    ///    a to właśnie stary, niedziałający pomocnik jest tym, co mamy wykryć.
    ///    Sonda, która wymaga nowego demona, milczy dokładnie tam, gdzie ma mierzyć.
    ///
    /// Pusta ścieżka nie przechodzi przez sito `isPlausibleMountPoint` w żadnej
    /// wersji pomocnika: demon odpowiada `-1, "Refused mount point."` i nie
    /// dotyka `bless`. Liczy się sama odpowiedź, nie jej treść — dlatego odmowa
    /// sita jest tutaj **wynikiem pozytywnym**.
    private static func zmierzZywotnosc() -> Bool {
        guard service.status == .enabled else { return false }
        do {
            try zawolaj(mountPoint: "", termin: terminZywotnosci)
            return true
        } catch Failure.bless {
            return true
        } catch {
            return false
        }
    }
}
