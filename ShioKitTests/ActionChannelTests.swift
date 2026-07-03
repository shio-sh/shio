import Testing
import Foundation
@testable import Shio

/// The approve channel's at-most-once rules. A re-tap is cheap; a double-"y"
/// into the *next* prompt is not — every rule here guards that asymmetry.
struct ActionChannelTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func action(_ id: String, session: String = "shio-app",
                        key: String = "y", age: TimeInterval?) -> CloudKitSignalService.FetchedAction {
        .init(id: id, sessionId: session, key: key,
              created: age.map { now.addingTimeInterval(-$0) })
    }

    @Test func freshConfirmedActionIsConsumed() {
        let got = CloudKitSignalService.consumable(
            records: [action("r1", age: 10)],
            deleteConfirmed: ["r1"], now: now, maxAge: 120)
        #expect(got.map(\.sessionId) == ["shio-app"])
        #expect(got.first?.key == "y")
    }

    @Test func staleActionIsConsumedButNeverInjected() {
        // Older than the TTL = a leftover written while the Mac was off.
        let got = CloudKitSignalService.consumable(
            records: [action("r1", age: 180)],
            deleteConfirmed: ["r1"], now: now, maxAge: 120)
        #expect(got.isEmpty)
    }

    @Test func unconfirmedDeleteIsNeverInjected() {
        // A failed delete re-fetches next poll — injecting now would double-answer.
        let got = CloudKitSignalService.consumable(
            records: [action("r1", age: 10)],
            deleteConfirmed: [], now: now, maxAge: 120)
        #expect(got.isEmpty)
    }

    @Test func newestWritePerSessionWins() {
        // Approve on the phone AND the watch in the same window → one keystroke.
        let got = CloudKitSignalService.consumable(
            records: [action("r1", key: "y", age: 60), action("r2", key: "n", age: 5)],
            deleteConfirmed: ["r1", "r2"], now: now, maxAge: 120)
        #expect(got.count == 1)
        #expect(got.first?.key == "n")
    }

    @Test func missingCreationDateIsDropped() {
        // No server timestamp = unverifiable freshness = never injected.
        let got = CloudKitSignalService.consumable(
            records: [action("r1", age: nil)],
            deleteConfirmed: ["r1"], now: now, maxAge: 120)
        #expect(got.isEmpty)
    }

    @Test func independentSessionsEachGetTheirAnswer() {
        let got = CloudKitSignalService.consumable(
            records: [action("r1", session: "shio-app", key: "y", age: 10),
                      action("r2", session: "shio-api", key: "n", age: 12)],
            deleteConfirmed: ["r1", "r2"], now: now, maxAge: 120)
        #expect(got.map(\.sessionId) == ["shio-api", "shio-app"])   // sorted, both present
    }
}
