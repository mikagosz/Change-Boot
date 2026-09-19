import Foundation

// Jedna binarka, trzy role.
//
// Uruchomiona przez użytkownika jest programem z oknem. Uruchomiona przez launchd
// z argumentem `--helper` jest demonem roota i nie tworzy niczego z AppKit.
// Uruchomiona z terminala ze znanym czasownikiem jest wierszem poleceń i kończy się
// kodem wyjścia, nie oknem.
// Rozdział musi stać tutaj, w `main.swift`, i dlatego `ChangeBootApp` nie ma
// `@main`: atrybut `@main` i plik `main.swift` wykluczają się w jednym module.
if CommandLine.arguments.contains(HelperNames.daemonArgument) {
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
