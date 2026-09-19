import Foundation

// Jedna binarka, trzy role.
//
// Uruchomiona przez użytkownika jest programem z oknem. Uruchomiona przez launchd
// z argumentem `--helper` jest demonem roota i nie tworzy niczego z AppKit.
// Uruchomiona z terminala ze znanym czasownikiem jest wierszem poleceń i kończy się
// kodem wyjścia, nie oknem.
// Rozdział musi stać tutaj, w `main.swift`, i dlatego `ChangeBootApp` nie ma
// `@main`: atrybut `@main` i plik `main.swift` wykluczają się w jednym module.
if HelperNames.czyWywolanieDemona(CommandLine.arguments) {
    // Druga zapora, niezależna od kształtu argumentów: demon bez uprawnień roota
    // nie ma po co wstawać. Usługa Macha jest zarejestrowana w domenie systemowej
    // i proces użytkownika i tak nigdy nie dostanie na niej połączenia — bez tego
    // sprawdzenia zostałaby po nim sama wisząca pętla zdarzeń.
    guard getuid() == 0 else {
        let tekst = CommandLineTool.t("--helper starts the privileged helper, and launchd does that for you. Install the helper in the app's Options, or type: change-boot help")
        FileHandle.standardError.write(Data((tekst + "\n").utf8))
        exit(CommandLineTool.Kod.zleUzycie.rawValue)
    }
    HelperDaemon.main()
}

// Trzecia rola: wiersz poleceń. Rozpoznawany po ZNANYM czasowniku, nie po „są
// jakieś argumenty" — macOS dokłada uruchamianym programom własne przełączniki
// (`-psn_0_…`, `-NSDocumentRevisionsDebugMode`), a program otwarty z Findera ma
// pokazać okno, a nie wypisać pomoc.
if CommandLineTool.czyPolecenie(CommandLine.arguments) {
    CommandLineTool.main(CommandLine.arguments)
}

ChangeBootApp.main()
