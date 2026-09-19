import Foundation

// Jedna binarka, dwie role.
//
// Uruchomiona przez użytkownika jest programem z oknem. Uruchomiona przez launchd
// z argumentem `--helper` jest demonem roota i nie tworzy niczego z AppKit.
// Rozdział musi stać tutaj, w `main.swift`, i dlatego `ChangeBootApp` nie ma
// `@main`: atrybut `@main` i plik `main.swift` wykluczają się w jednym module.
if CommandLine.arguments.contains(HelperNames.daemonArgument) {
    HelperDaemon.main()
}

ChangeBootApp.main()
