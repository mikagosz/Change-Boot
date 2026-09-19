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

        // 🔴 Dowiązanie odrzucamy, zanim cokolwiek pójdzie za nim dalej.
        // Zmierzone na maszynie [U] 2026-09-19: pod `/Volumes` leży
        // `Macintosh HD -> /`, a `fileExists` nie odróżnia go od katalogu.
        // `lstat` nie idzie za dowiązaniem, `stat` by poszedł.
        var opis = stat()
        guard lstat(path, &opis) == 0 else { return false }
        guard opis.st_mode & S_IFMT == S_IFDIR else { return false }

        // 🔴 Ścieżka ma **być** punktem montowania, nie leżeć pod nim.
        // `statfs` oddaje punkt montowania woluminu, w którym ścieżka siedzi;
        // gdy to nie jest to samo, dostaliśmy zwykły katalog na czymś innym.
        // To zdejmuje cały pomysł „użytkownik montuje własny obraz i podaje
        // w nim podkatalog" bez sprawdzania czegokolwiek po nazwie.
        var system = statfs()
        guard statfs(path, &system) == 0 else { return false }
        let punkt = withUnsafeBytes(of: &system.f_mntonname) { bufor -> String in
            guard let poczatek = bufor.baseAddress else { return "" }
            return String(cString: poczatek.assumingMemoryBound(to: CChar.self))
        }
        guard punkt == path else { return false }

        // 🔴 Tylko wolumin miejscowy. Zmierzone u [U]: pod `/Volumes` stoją dwa
        // udziały SMB „mounted by maczek". `bless` na udziale sieciowym nie ma
        // sensu, a najgorszy przypadek to maszyna wskazująca po restarcie
        // na wolumin, którego nie ma.
        guard system.f_flags & UInt32(MNT_LOCAL) != 0 else { return false }

        return true
    }
}
