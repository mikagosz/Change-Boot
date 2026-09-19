import Foundation
import os

/// Strona uprzywilejowana: ta sama binarka, uruchomiona przez launchd jako root.
///
/// Żyje w tym samym module co program celowo. Osobny target znaczy osobny podpis,
/// osobną wersję i dwa miejsca, w których trzeba pamiętać o tej samej nazwie usługi;
/// jedna binarka z przełącznikiem w `main.swift` nie ma jak się rozjechać sama ze sobą.
///
/// Tryb demona rozpoznaje `HelperNames.daemonArgument` w argumentach. Nic z AppKit
/// ani SwiftUI tutaj nie wchodzi — proces roota nie ma sesji okienkowej.
enum HelperDaemon {

    static let log = Logger(subsystem: "com.mikagosz.ChangeBoot", category: "helper")

    /// Uruchamia nasłuch XPC i **nie wraca**.
    static func main() -> Never {
        let delegate = HelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: HelperNames.machService)
        listener.delegate = delegate
        listener.resume()
        log.notice("pomocnik wystartował, usługa \(HelperNames.machService, privacy: .public)")
        // Demon z MachServices nie kończy się sam — launchd trzyma go na żądanie.
        RunLoop.current.run()
        exit(0)
    }
}

/// Wpuszcza wyłącznie połączenia od programu podpisanego tym samym certyfikatem.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // 🔴 Wymaganie MUSI być ustawione przed `resume()`. Połączenie wznowione
        // i dopiero potem obwarowane zdąży przyjąć wiadomość od kogokolwiek.
        //
        // `setCodeSigningRequirement` nic nie zwraca i niczego nie rzuca: pilnuje
        // tego system i sam unieważnia połączenie, gdy rozmówca nie spełnia
        // wymagania. Rzuca wyjątkiem Objective-C tylko wtedy, gdy sam łańcuch
        // wymagania jest niepoprawny — czyli przy błędzie w `HelperTrust`.
        connection.setCodeSigningRequirement(HelperTrust.requirement)

        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

/// Czynności wykonywane z uprawnieniami roota.
final class HelperService: NSObject, HelperProtocol {

    func version(reply: @escaping (String) -> Void) {
        reply(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
    }

    /// Ustawia dysk startowy. Przychodzi **punkt montowania**, nie polecenie.
    ///
    /// `bless` wołany jest przez `Process` z tablicą argumentów, więc nie ma tu
    /// powłoki, która mogłaby cokolwiek zinterpretować — apostrof, spacja czy
    /// średnik w nazwie woluminu są zwykłymi znakami. Stary `do shell script`
    /// składał jeden łańcuch i musiał je oescapować ręcznie.
    func setStartupDisk(mountPoint: String, reply: @escaping (Int32, String) -> Void) {
        guard Self.isPlausibleMountPoint(mountPoint) else {
            HelperDaemon.log.error("odrzucony punkt montowania")
            reply(-1, "Refused mount point.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/bless")
        process.arguments = ["--mount", mountPoint, "--setBoot"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            reply(-1, error.localizedDescription)
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        HelperDaemon.log.notice("bless zakończony kodem \(process.terminationStatus, privacy: .public)")
        reply(process.terminationStatus, text)
    }

    /// Sito na to, co wolno podać jako cel.
    ///
    /// Klient jest już sprawdzony podpisem, więc to nie jest pierwsza linia obrony
    /// — to druga. Proces roota nie powinien podawać `bless` czegokolwiek tylko
    /// dlatego, że rozmówca miał właściwy certyfikat.
    static func isPlausibleMountPoint(_ path: String) -> Bool {
        guard path == "/" || path.hasPrefix("/Volumes/") else { return false }
        guard !path.contains("..") else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return true
    }
}
