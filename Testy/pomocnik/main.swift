// Sprawdzian headless czystego startu i pomocnika.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-pomocnik Testy/pomocnik/main.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/BootSystem.swift \
//          Change-Boot/BootActions.swift Change-Boot/PrivilegedShell.swift \
//          Change-Boot/HelperClient.swift Change-Boot/HelperProtocol.swift \
//          Change-Boot/HelperDaemon.swift Change-Boot/AppBundle.swift && /tmp/test-pomocnik
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

// 🔴 P2-11 z audytu. Sito do 0.2.12 przyjmowało wszystko pod `/Volumes`, co
// istnieje i jest katalogiem — a `fileExists` nie odróżnia dowiązania, udziału
// sieciowego ani podkatalogu na cudzym woluminie. Poniższe przypadki są wzięte
// z prawdziwej maszyny, nie wymyślone: `Macintosh HD -> /` i udziały SMB
// „mounted by maczek" stoją tam na co dzień.

/// Punkty montowania widziane przez system, z podziałem na miejscowe i resztę.
func zamontowane() -> (miejscowe: [String], sieciowe: [String]) {
    var bufor: UnsafeMutablePointer<statfs>?
    let ile = getmntinfo(&bufor, MNT_NOWAIT)
    guard ile > 0, let lista = bufor else { return ([], []) }
    var miejscowe: [String] = [], sieciowe: [String] = []
    for i in 0..<Int(ile) {
        var wpis = lista[i]
        let punkt = withUnsafeBytes(of: &wpis.f_mntonname) { b -> String in
            guard let p = b.baseAddress else { return "" }
            return String(cString: p.assumingMemoryBound(to: CChar.self))
        }
        guard punkt.hasPrefix("/Volumes/") else { continue }
        if wpis.f_flags & UInt32(MNT_LOCAL) != 0 { miejscowe.append(punkt) }
        else { sieciowe.append(punkt) }
    }
    return (miejscowe, sieciowe)
}

let punkty = zamontowane()
print("  miejscowe pod /Volumes: \(punkty.miejscowe)")
print("  sieciowe pod /Volumes:  \(punkty.sieciowe)")

// Kontrola dodatnia sita: coś, co NA PEWNO przechodzi, musi przejść — inaczej
// wszystkie zera wyżej znaczyłyby „sito zwraca fałsz na wszystko".
// 🔴 KAŻDY miejscowy punkt montowania ma przejść, nie tylko pierwszy z brzegu.
// Zaostrzone sito, które przepuszcza `Recovery`, a odrzuca `Mac Lab`, byłoby
// gorsze od poprzedniego — a różnicy nie widać, dopóki sprawdza się jeden wpis.
if punkty.miejscowe.isEmpty {
    print("  ⚠ brak podpiętego woluminu miejscowego — kontrola dodatnia POMINIĘTA")
    pominiete += 1
}
for miejscowy in punkty.miejscowe {
    sprawdz("kontrola dodatnia — miejscowy punkt montowania przechodzi (\(miejscowy))",
            HelperService.isPlausibleMountPoint(miejscowy))
}

for udzial in punkty.sieciowe {
    sprawdz("udział sieciowy odrzucony (\(udzial))",
            !HelperService.isPlausibleMountPoint(udzial))
}
if punkty.sieciowe.isEmpty {
    print("  ⚠ brak podpiętego udziału sieciowego — sprawdzenie POMINIĘTE")
    pominiete += 1
}

// Dowiązanie. Jeśli akurat nie ma go pod ręką, robimy własne w katalogu
// tymczasowym — poza `/Volumes`, więc sito i tak je odrzuci po prefiksie;
// prawdziwy przypadek `/Volumes/Macintosh HD` sprawdzamy tylko wtedy, gdy jest.
if let dowiazanie = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes"))?
    .map({ "/Volumes/\($0)" })
    .first(where: { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) != nil }) {
    sprawdz("dowiązanie pod /Volumes odrzucone (\(dowiazanie))",
            !HelperService.isPlausibleMountPoint(dowiazanie))
} else {
    print("  ⚠ brak dowiązania pod /Volumes — sprawdzenie POMINIĘTE")
    pominiete += 1
}

// Podkatalog na prawdziwym woluminie: istnieje, jest katalogiem, leży pod
// `/Volumes` — i ma NIE przejść, bo nie jest punktem montowania.
if let miejscowy = punkty.miejscowe.first,
   let podkatalog = (try? FileManager.default.contentsOfDirectory(atPath: miejscowy))?
       .map({ "\(miejscowy)/\($0)" })
       .first(where: { sciezka in
           var czyKatalog: ObjCBool = false
           return FileManager.default.fileExists(atPath: sciezka, isDirectory: &czyKatalog)
               && czyKatalog.boolValue
               && (try? FileManager.default.destinationOfSymbolicLink(atPath: sciezka)) == nil
       }) {
    sprawdz("podkatalog na woluminie odrzucony (\(podkatalog))",
            !HelperService.isPlausibleMountPoint(podkatalog))
} else {
    print("  ⚠ brak podkatalogu do sprawdzenia — POMINIĘTE")
    pominiete += 1
}

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

print("\nWybór roli demona — P1-07 z audytu 2026-09-19")

// 🔴 Do 0.2.8 rozstrzygało `arguments.contains("--helper")`, więc rola demona
// wygrywała z każdym czasownikiem. `change-boot list --helper` wchodziło
// w pętlę zdarzeń i wisiało bez końca, nie wypisując ani jednego znaku.
sprawdz("launchd: dokładnie jeden argument --helper to wywołanie demona",
        HelperNames.czyWywolanieDemona(["/x/Change-Boot", "--helper"]))
sprawdz("--helper doklejone do czasownika NIE jest wywołaniem demona",
        !HelperNames.czyWywolanieDemona(["/x/Change-Boot", "list", "--helper"]))
sprawdz("--helper przed czasownikiem też NIE",
        !HelperNames.czyWywolanieDemona(["/x/Change-Boot", "--helper", "list"]))
sprawdz("samo uruchomienie bez argumentów NIE jest wywołaniem demona",
        !HelperNames.czyWywolanieDemona(["/x/Change-Boot"]))
sprawdz("przełącznik systemowy macOS NIE jest wywołaniem demona",
        !HelperNames.czyWywolanieDemona(["/x/Change-Boot", "-psn_0_12345"]))

print("\nNazwy mostu")

sprawdz("etykieta demona zgadza się z nazwą plistu",
        HelperNames.plistName == HelperNames.label + ".plist")
sprawdz("usługa Macha nosi nazwę etykiety",
        HelperNames.machService == HelperNames.label)

print("\nAwarie: \(awarie), pominięte: \(pominiete)")
exit(awarie == 0 ? 0 : 1)
