import Foundation

enum AppleScript {
    /// Uruchamia skrypt i zwraca jego wynik jako tekst.
    /// Anulowanie przez użytkownika (-128) zgłasza jako `BootError.cancelled`.
    @discardableResult
    static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw BootError.blessFailed(String(localized: "Could not build the helper script."))
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { throw BootError.cancelled }
            let message = (error[NSAppleScript.errorMessage] as? String)
                ?? String(localized: "Unknown error (\(code)).")
            throw BootError.blessFailed(message)
        }
        return result.stringValue ?? ""
    }
}

/// Droga zastępcza do uprawnień roota: hasło administratora brane wprost od
/// człowieka, gdy pomocnika nie ma albo nie odpowiada.
///
/// 🔴 **Hasło ma być pytane tam, gdzie człowiek patrzy.** To jest cała treść tego
/// typu. Program ma dwie twarze — okno i terminal — a do 0.2.19 obie prowadziły
/// do jednego systemowego okna hasła. Zgłoszenie [U] 2026-09-20: widok
/// pełnoekranowy wyrzucał okienko dialogowe, choć na ekranie nie było niczego
/// okienkowego. Z terminala pyta więc `sudo`, w tym samym oknie i tym samym
/// rytmem, w jakim pyta każde inne polecenie systemowe.
enum PrivilegedShell {

    /// Wykonuje polecenie z uprawnieniami administratora przez systemowe okno hasła.
    ///
    /// Zostaje jako droga dla programu okienkowego. Wąskie zastosowanie — patrz
    /// `ustawDyskStartowy`, które wybiera między tą drogą a `sudo`.
    @discardableResult
    static func run(_ command: String) throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return try AppleScript.run(
            "do shell script \"\(escaped)\" with administrator privileges")
    }

    // MARK: - Dysk startowy bez pomocnika

    /// Ustawia dysk startowy, pytając o hasło drogą pasującą do tego, skąd
    /// program został uruchomiony.
    ///
    /// Jedno miejsce, bo do 0.2.19 `BootActions` składał to wywołanie dwa razy,
    /// każdy raz z własnym cytowaniem apostrofów.
    static func ustawDyskStartowy(mountPoint: String) throws {
        if Terminal.czyTerminal {
            try przezSudo(mountPoint: mountPoint)
        } else {
            let quoted = mountPoint.replacingOccurrences(of: "'", with: "'\\''")
            _ = try run("/usr/sbin/bless --mount '\(quoted)' --setBoot 2>&1")
        }
    }

    private static let sudo = "/usr/bin/sudo"

    /// Hasło w terminalu, potem `bless` biletem z tego hasła.
    ///
    /// 🔴 **Dwa wywołania `sudo`, nie jedno.** Jedno oddałoby kod 1 zarówno wtedy,
    /// gdy człowiek nie podał hasła, jak i wtedy, gdy `bless` odmówił — a to dwie
    /// różne rzeczy: pierwsza znaczy „nic się nie stało", druga jest usterką do
    /// pokazania. `sudo -v` kończy się zerem **wyłącznie** po udanym
    /// uwierzytelnieniu, więc granica między nimi idzie dokładnie tam, gdzie trzeba.
    private static func przezSudo(mountPoint: String) throws {
        print("")
        print(CommandLineTool.t("Change-Boot needs administrator rights to set the startup disk."))
        // Bufor na ekran, zanim `sudo` napisze swój monit — inaczej monit potrafi
        // wyjść przed zdaniem, które go tłumaczy.
        fflush(stdout)

        guard uwierzytelnij() else { throw BootError.cancelled }

        let proces = Process()
        proces.executableURL = URL(fileURLWithPath: sudo)
        // `-n`, czyli żadnego drugiego monitu: hasło padło przed chwilą przy `-v`,
        // więc albo bilet jest ważny, albo dzieje się coś, o czym trzeba powiedzieć.
        // Drugi monit w środku wykonywania wygląda jak pętla.
        proces.arguments = ["-n", "/usr/sbin/bless", "--mount", mountPoint, "--setBoot"]
        let rura = Pipe()
        proces.standardOutput = rura
        proces.standardError = rura

        do { try proces.run() } catch {
            throw BootError.blessFailed(error.localizedDescription)
        }
        let dane = rura.fileHandleForReading.readDataToEndOfFile()
        proces.waitUntilExit()

        guard proces.terminationStatus == 0 else {
            let tekst = String(data: dane, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BootError.blessFailed("bless (\(proces.terminationStatus))\n\(tekst)")
        }
    }

    /// Bierze hasło w terminalu i **nic poza tym** nie robi.
    ///
    /// Wejście, wyjście i błędy zostają terminalowe — nie przechwytujemy ich
    /// w rurę, bo `sudo` sam gasi echo i sam rysuje monit, a przez rurę nie
    /// miałby gdzie zrobić ani jednego, ani drugiego.
    private static func uwierzytelnij() -> Bool {
        let proces = Process()
        proces.executableURL = URL(fileURLWithPath: sudo)
        // Bez `-p`: monit zostaje ten, który `sudo` pisze od zawsze, więc wygląda
        // dokładnie tak, jak każde inne pytanie o hasło w tym terminalu. Zdanie
        // tłumaczące, dlaczego program o nie prosi, poszło wierszem wyżej — i to
        // ono jest przetłumaczone, a nie monit systemowego narzędzia.
        proces.arguments = ["-v"]
        do { try proces.run() } catch { return false }
        proces.waitUntilExit()
        return proces.terminationStatus == 0
    }
}
