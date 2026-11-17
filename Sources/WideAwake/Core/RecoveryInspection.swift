import Foundation

/// Read-only inspection of saved intent and recovery entries. It never
/// observes hardware or performs recovery; the two files are not one snapshot.
enum RecoveryInspection {
    struct SessionStatus: Encodable {
        let status: String
        let endsAt: Date?
        let error: String?
    }
    struct JournalStatus: Encodable {
        let status: String
        let pending: [String]
        let error: String?
    }
    struct Report: Encodable {
        let session: SessionStatus
        let journal: JournalStatus
        let observedState: String = "not_observed"
        let effects: String = "not_attempted"
        let atomicSnapshot: Bool = false
    }

    static func inspect(root: URL) -> (Report, Bool) {
        let store = Store(paths: Paths(root: root))
        var failed = false
        let session: SessionStatus
        do {
            if let value = try store.loadSession() {
                session = SessionStatus(status: "present", endsAt: value.endsAt, error: nil)
            } else {
                session = SessionStatus(status: "missing", endsAt: nil, error: nil)
            }
        } catch {
            failed = true
            session = SessionStatus(status: "unreadable", endsAt: nil, error: error.localizedDescription)
        }
        let journal: JournalStatus
        do {
            if let value = try store.loadState() {
                var pending: [String] = []
                if value.sleepDisabledByUs { pending.append("sleep") }
                if value.lowPowerSetByUs { pending.append("low_power") }
                if !value.frozenProcesses.isEmpty { pending.append("processes") }
                if value.dockerFrozen { pending.append("docker") }
                if value.savedOutputVolume != nil || value.savedMuted != nil { pending.append("audio") }
                if value.savedDisplayBrightness != nil { pending.append("display") }
                if value.savedKeyboardBrightness != nil { pending.append("keyboard") }
                if value.displayRestoredUnderLowPower != nil { pending.append("display_followup") }
                journal = JournalStatus(status: "present", pending: pending, error: nil)
            } else {
                journal = JournalStatus(status: "missing", pending: [], error: nil)
            }
        } catch {
            failed = true
            journal = JournalStatus(status: "unreadable", pending: [], error: error.localizedDescription)
        }
        return (Report(session: session, journal: journal), failed)
    }
}
