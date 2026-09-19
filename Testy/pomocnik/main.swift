// Sprawdzian headless czystego startu i pomocnika.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-pomocnik Testy/pomocnik/main.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/BootSystem.swift \
//          Change-Boot/BootActions.swift Change-Boot/PrivilegedShell.swift \
//          Change-Boot/HelperClient.swift Change-Boot/HelperProtocol.swift \
//          Change-Boot/HelperDaemon.swift && /tmp/test-pomocnik
//
// Nic tutaj nie restartuje maszyny ani nie instaluje demona: sprawdzane jest to,
// co da się sprawdzić bez skutków ubocznych — kształt polecenia restartu, sito
// punktów montowania i zgodność wymagania podpisu z tym, co naprawdę wypisuje
// `codesign` na zbudowanym programie.

import Foundation

var awarie = 0
var pominiete = 0

func sprawdz(_ opis: String, _ warunek: @autoclosure () -> Bool) {
    if warunek() {
        print("  ✓ \(opis)")
    } else {
        print("  ✗ \(opis)")
        awarie += 1
    }
}

func pomin(_ opis: String, _ powod: String) {
    print("  — \(opis)  (pominięte: \(powod))")
    pominiete += 1
}

print("Czysty start — kształt polecenia restartu")

// 🔴 To jest zabezpieczenie dokładnie tej usterki, która wróciła 2026-09-19.
// Gołe „restart" zapisuje stan sesji ZAWSZE, cokolwiek stoi w TALLogoutSavesState —
// mówi to wprost słownik System Events. Bez tego parametru czysty start jest ozdobą.
sprawdz("restart idzie z parametrem state saving preference",
        BootActions.restartScript.contains("with state saving preference"))
sprawdz("restart idzie przez System Events, nie przez shutdown -r",
        BootActions.restartScript.contains("System Events")
            && !BootActions.restartScript.contains("shutdown"))

print("\nSito punktów montowania pomocnika")

sprawdz("korzeń wolno", HelperService.isPlausibleMountPoint("/"))
sprawdz("katalog systemowy poza /Volumes odrzucony",
        !HelperService.isPlausibleMountPoint("/etc"))
sprawdz("wyjście w górę drzewa odrzucone",
        !HelperService.isPlausibleMountPoint("/Volumes/../etc"))
sprawdz("nieistniejąca ścieżka odrzucona",
        !HelperService.isPlausibleMountPoint("/Volumes/Nie ma takiego dysku 4f1a"))
sprawdz("plik zamiast katalogu odrzucony",
        !HelperService.isPlausibleMountPoint("/etc/hosts"))
// Kontrola dodatnia sita: coś, co NA PEWNO przechodzi, musi przejść — inaczej
// wszystkie zera wyżej znaczyłyby „sito zwraca fałsz na wszystko".
sprawdz("kontrola dodatnia — istniejący katalog w /Volumes przechodzi", {
    let sciezki = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
    guard let pierwszy = sciezki.first else { return true }
    return HelperService.isPlausibleMountPoint("/Volumes/\(pierwszy)")
}())

print("\nWymaganie podpisu")

/// Ścieżka do zbudowanego programu, jeśli da się ją ustalić bez zgadywania.
func zbudowanyProgram() -> String? {
    let kandydaci = [
        "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"
    ]
    for katalog in kandydaci {
        guard let wpisy = try? FileManager.default.contentsOfDirectory(atPath: katalog) else { continue }
        for wpis in wpisy where wpis.hasPrefix("Change-Boot-") {
            let sciezka = "\(katalog)/\(wpis)/Build/Products/Debug/Change-Boot.app"
            if FileManager.default.fileExists(atPath: sciezka) { return sciezka }
        }
    }
    return nil
}

if let program = zbudowanyProgram() {
    let proces = Process()
    proces.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    proces.arguments = ["-d", "-r-", program]
    let rura = Pipe()
    proces.standardOutput = rura
    proces.standardError = rura
    try? proces.run()
    let wyjscie = String(data: rura.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
    proces.waitUntilExit()

    // Wymaganie w kodzie musi zgadzać się z podpisem zbudowanego programu, inaczej
    // pomocnik odrzuci własny program i nikt się nie dowie dlaczego — błędu przy
    // kompilacji tu nie ma żadnego.
    let odcisk = HelperTrust.requirement
        .components(separatedBy: "H\"").last?
        .components(separatedBy: "\"").first ?? ""
    sprawdz("odcisk certyfikatu z HelperTrust zgadza się z podpisem programu",
            !odcisk.isEmpty && wyjscie.lowercased().contains(odcisk.lowercased()))
    sprawdz("wymaganie wiąże też identyfikator programu",
            wyjscie.contains("identifier \"com.mikagosz.ChangeBoot\""))
} else {
    pomin("zgodność wymagania podpisu z codesign", "brak zbudowanego programu w DerivedData")
}

print("\nNazwy mostu")

sprawdz("etykieta demona zgadza się z nazwą plistu",
        HelperNames.plistName == HelperNames.label + ".plist")
sprawdz("usługa Macha nosi nazwę etykiety",
        HelperNames.machService == HelperNames.label)

print("\nAwarie: \(awarie), pominięte: \(pominiete)")
exit(awarie == 0 ? 0 : 1)
