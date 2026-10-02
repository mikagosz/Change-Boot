import Foundation
import ServiceManagement

/// When the "install the helper again" reminder is due — kept apart from `HelperAfterUpdate`
/// so `Testy/poaktualizacji` can compile it without ErrorUpdate, AppKit or the event log.
enum HelperAfterUpdateRule {

    /// The text shown as "previous → current", or `nil` when there is nothing to remind about:
    /// no update on this launch, or no helper registered (a user who never installed it is
    /// not bothered).
    static func reminder(previousVersion: String?, currentVersion: String?,
                         helperStatus: SMAppService.Status) -> String? {
        guard let previousVersion, let currentVersion else { return nil }
        switch helperStatus {
        case .notRegistered, .notFound: return nil
        default: return "\(previousVersion) → \(currentVersion)"
        }
    }
}
