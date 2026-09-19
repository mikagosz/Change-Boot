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
        case connection(String)
        case bless(code: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return String(localized: "The privileged helper is not installed.")
            case .needsApproval:
                return String(localized: "The helper is waiting for your approval in System Settings → General → Login Items.")
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
        try service.unregister()
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Rozmowa

    /// Ustawia dysk startowy rękami pomocnika. Rzuca, gdy pomocnika nie ma —
    /// decyzję o drodze zastępczej podejmuje `BootActions`, nie ten typ.
    static func setStartupDisk(mountPoint: String) throws {
        switch service.status {
        case .enabled:          break
        case .requiresApproval: throw Failure.needsApproval
        default:                throw Failure.notInstalled
        }

        let connection = NSXPCConnection(machServiceName: HelperNames.machService,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        var connectionError: String?
        // Proxy synchroniczne: blok odpowiedzi wykonuje się przed powrotem
        // z wywołania, więc nie ma tu ani semafora, ani pętli oczekiwania.
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { error in
            connectionError = error.localizedDescription
        } as? HelperProtocol

        guard let proxy, connectionError == nil else {
            throw Failure.connection(connectionError ?? String(localized: "No proxy object."))
        }

        var code: Int32 = -1
        var output = ""
        proxy.setStartupDisk(mountPoint: mountPoint) { odpowiedzKod, odpowiedzTekst in
            code = odpowiedzKod
            output = odpowiedzTekst
        }

        if let connectionError { throw Failure.connection(connectionError) }
        guard code == 0 else { throw Failure.bless(code: code, output: output) }
    }
}
