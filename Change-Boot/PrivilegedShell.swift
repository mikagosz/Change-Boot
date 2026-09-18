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

enum PrivilegedShell {

    /// Wykonuje polecenie z uprawnieniami administratora.
    ///
    // SKRÓT: uprawnienia bierzemy przez „do shell script … with administrator
    // privileges”. Sufit: systemowe okno hasła przy każdym przełączeniu i brak
    // własnego, podpisanego kanału — przy dystrybucji poza tę maszynę to za mało.
    // Droga wyjścia: uprzywilejowany helper rejestrowany przez SMAppService,
    // rozmowa po XPC, hasło raz przy instalacji.
    @discardableResult
    static func run(_ command: String) throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return try AppleScript.run(
            "do shell script \"\(escaped)\" with administrator privileges")
    }
}
