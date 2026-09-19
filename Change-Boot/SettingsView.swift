import AppKit
import SwiftUI
import ServiceManagement

/// Ekran ustawień — **jedyne** miejsce, w którym stoją opcje programu.
///
/// Powstał na polecenie [U] 2026-09-19: *„wstaw w oknie głównym przycisk «opcje»,
/// po kliknięciu przechodzimy na okno ustawień i tam niech będą wszystkie opcje
/// i ustawienia"*. Do 0.1.17 ustawienia dokładały się pojedynczo do stopki okna
/// głównego i po trzecim przełączniku zrobiła się z tego zbieranina.
///
/// Wchodzi **w to samo okno**, nie w nowe — doprecyzowanie [U] chwilę później:
/// *„nie kolejne okno tylko opcje mają się w tym samym otworzyć"*. Stąd brak
/// własnej ramki: rozmiar narzuca okno główne.
///
/// Zasada na przyszłość: **nowe ustawienie idzie tutaj**, nie do stopki listy.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var language = AppLanguage.current
    /// Język z chwili otwarcia okna — patrz `LanguageMenu`: wybór zapisuje się od
    /// razu, więc bez tego przycisk restartu byłby wyłączony zawsze.
    @State private var languageAtOpen = AppLanguage.current
    @State private var helperStatus = HelperClient.statusDescription
    @State private var helperFailure: String?
    @State private var busy = false

    var body: some View {
        @Bindable var configuration = model.configuration

        Form {
            Section("Switching") {
                Toggle("Clean start — do not reopen apps and windows",
                       isOn: $configuration.cleanStartByDefault)
            }

            Section("Menu bar icon") {
                Toggle("Show icon in the menu bar",
                       isOn: $configuration.showsMenuBarIcon)
                Toggle("Menu bar icon without colours",
                       isOn: $configuration.monochromeMenuBarIcon)
                    .disabled(!configuration.showsMenuBarIcon)
                Toggle("Hide the Dock icon when the window is closed",
                       isOn: $configuration.hidesDockIcon)
                    .disabled(!configuration.showsMenuBarIcon)
                    .onChange(of: configuration.hidesDockIcon) { _, _ in
                        AppDelegate.aktualizujObecnoscWDocku()
                    }
            }

            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .onChange(of: language) { _, new in AppLanguage.apply(new) }

                if language != languageAtOpen {
                    HStack {
                        Text("Change-Boot has to restart to load the other language.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Change-Boot") { AppLanguage.relaunch() }
                    }
                }
            }

            Section("Password") {
                Text("Changing the startup disk needs administrator rights. Install the helper once and Change-Boot stops asking for your password on every switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: HelperClient.isReady ? "lock.open" : "lock")
                        .foregroundStyle(HelperClient.isReady ? .green : .secondary)
                    Text(helperStatus)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if HelperClient.status == .requiresApproval {
                        Button("Open System Settings") { HelperClient.openLoginItemsSettings() }
                    }
                    if HelperClient.isReady {
                        Button("Remove helper") { run(HelperClient.uninstall) }
                    } else {
                        Button("Install helper") { run(HelperClient.install) }
                    }
                }
                .disabled(busy)

                if HelperClient.isInTemporaryLocation && !HelperClient.isReady {
                    Label("Move Change-Boot to the Applications folder first. The helper remembers where the app was when you installed it, so registering it from a build folder stops working after the next build.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Change-Boot", isPresented: Binding(
            get: { helperFailure != nil },
            set: { if !$0 { helperFailure = nil } })) {
            Button("OK", role: .cancel) { helperFailure = nil }
        } message: {
            Text(helperFailure ?? "")
        }
    }

    private func run(_ action: @escaping () throws -> Void) {
        busy = true
        do {
            try action()
        } catch {
            helperFailure = error.localizedDescription
        }
        // Stan po rejestracji potrafi wejść z opóźnieniem — odczytujemy go z
        // `SMAppService`, a nie zakładamy, że skoro nie rzuciło, to jest włączony.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            busy = false
        }
    }
}
