import AppKit
import ErrorUpdate
import ServiceManagement
import SwiftUI

/// Reminds the user to remove and install the helper again after Change-Boot was updated.
///
/// Why a reminder and not an automatic re-registration: see `Updates` — the helper stays tied to
/// the bundle it was registered from, and re-registering it by itself was measured to fail
/// ("not allowed to bootstrap", then "requires approval"). The user's own Remove → Install, a few
/// seconds apart, works; this window offers exactly those two steps.
///
/// It relies on ErrorUpdate's `completedUpdate` (1.0.6): the first launch of a newer version,
/// whatever installed it — the in-app update, the `.pkg` or a manual copy. A user who never
/// installed the helper is not bothered. Until the helper is installed again, Options → Password
/// keeps a line about it (decision [U] 2026-10-02: "change-boot ma przypominać o reinstalacji
/// pomocnika po aktualizacji").
@MainActor
final class HelperAfterUpdate: ObservableObject {
    static let shared = HelperAfterUpdate()

    /// "0.2.23 → 0.2.24" while the reinstall is still owed; survives restarts.
    static let pendingKey = "helperReinstallAfterUpdate"

    @Published private(set) var pending: String?
    @Published private(set) var status: SMAppService.Status = HelperClient.status
    @Published private(set) var failure: String?
    @Published private(set) var busy = false

    private var window: NSWindow?

    private init() {
        pending = UserDefaults.standard.string(forKey: Self.pendingKey)
    }

    /// Called once at launch, after ErrorUpdate is configured.
    func noteLaunch(_ update: CompletedUpdate?, helperStatus: SMAppService.Status) {
        guard let text = HelperAfterUpdateRule.reminder(previousVersion: update?.previousVersion,
                                                        currentVersion: update?.currentVersion,
                                                        helperStatus: helperStatus) else { return }
        pending = text
        UserDefaults.standard.set(text, forKey: Self.pendingKey)
        showWindow()
    }

    /// The helper was installed again (from here or from Options).
    func helperInstalled() {
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    func remove() {
        run(.usunieciePomocnika) { try HelperClient.uninstall() }
    }

    func install() {
        run(.instalacjaPomocnika) {
            if try HelperClient.install() == .gotowy {
                self.helperInstalled()
            }
        }
    }

    private func run(_ czynnosc: EventLog.Czynnosc, _ action: () throws -> Void) {
        busy = true
        failure = nil
        do {
            try action()
            EventLog.zapisz(czynnosc, skutek: .udane, zrodlo: .okno)
        } catch {
            failure = error.localizedDescription
            EventLog.zapisz(czynnosc, skutek: .nieudane, zrodlo: .okno, szczegol: error.localizedDescription)
        }
        // The state after (un)registering can arrive late — read it from SMAppService.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.status = HelperClient.status
            if self.status == .enabled, czynnosc == .instalacjaPomocnika { self.helperInstalled() }
            self.busy = false
        }
    }

    func showWindow() {
        status = HelperClient.status
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Change-Boot — Helper")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelperAfterUpdateView(model: self))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

private struct HelperAfterUpdateView: View {
    @ObservedObject var model: HelperAfterUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = model.pending {
                Label("Change-Boot was updated (\(pending))", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Text("The helper is still tied to the previous version and stops answering after the next restart. Remove it and install it again — until then Change-Boot asks for your password on every switch.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("The helper is installed again.", systemImage: "checkmark.circle")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            if model.status == .requiresApproval {
                Text("macOS is waiting for your approval in System Settings → General → Login Items.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = model.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                if model.status == .requiresApproval {
                    Button("Open System Settings") { HelperClient.openLoginItemsSettings() }
                }
                if model.pending == nil {
                    Button("Close") { model.closeWindow() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later") { model.closeWindow() }
                    if model.status == .enabled {
                        Button("Remove helper") { model.remove() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Install helper") { model.install() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .disabled(model.busy)
        }
        .padding(20)
        .frame(width: 440)
    }
}
