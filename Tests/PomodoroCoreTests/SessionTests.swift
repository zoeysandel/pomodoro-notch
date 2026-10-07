import XCTest
@testable import PomodoroCore

final class SessionTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 10_000)

    func testPauseAndResumePreserveRemainingTime() {
        var session = Session()
        session.start(task: "Presentation", kind: .focus, duration: 1_500, at: start)
        session.pause(at: start.addingTimeInterval(123))
        XCTAssertEqual(session.remaining, 1_377)
        XCTAssertEqual(session.secondsLeft(at: start.addingTimeInterval(9_000)), 1_377)
        session.resume(at: start.addingTimeInterval(9_000))
        XCTAssertEqual(session.secondsLeft(at: start.addingTimeInterval(9_100)), 1_277)
    }

    func testCompletionHappensExactlyOnceAfterSleep() {
        var session = Session()
        session.start(task: "Focus", kind: .focus, duration: 1_500, at: start)
        XCTAssertFalse(session.advance(to: start.addingTimeInterval(1_499)))
        XCTAssertTrue(session.advance(to: start.addingTimeInterval(3_000)))
        XCTAssertFalse(session.advance(to: start.addingTimeInterval(3_001)))
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.secondsLeft(at: start.addingTimeInterval(3_001)), 0)
    }

    func testRunningSessionSurvivesPersistence() throws {
        var session = Session()
        session.start(task: "Persist me", kind: .focus, duration: 60, at: start)
        let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(session, restored)
        XCTAssertEqual(restored.secondsLeft(at: start.addingTimeInterval(20)), 40)
    }

    func testPauseAtDeadlineCompletesInsteadOfResumingExpiredSession() {
        var session = Session()
        session.start(task: "Done", kind: .focus, duration: 2, at: start)
        XCTAssertTrue(session.pause(at: start.addingTimeInterval(2)))
        XCTAssertFalse(session.pause(at: start.addingTimeInterval(3)))
        XCTAssertFalse(session.advance(to: start.addingTimeInterval(3)))
        session.resume(at: start.addingTimeInterval(4))
        XCTAssertEqual(session.phase, .completed)
    }

    func testPausingBeforeDeadlineDoesNotEmitCompletion() {
        var session = Session()
        session.start(task: "Focus", kind: .focus, duration: 60, at: start)
        XCTAssertFalse(session.pause(at: start.addingTimeInterval(30)))
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.secondsLeft(at: start.addingTimeInterval(100)), 30)
        XCTAssertFalse(session.pause(at: start.addingTimeInterval(100)))
    }

    func testStopResetsAndBreakHasItsOwnDuration() {
        var session = Session()
        session.start(task: "Break", kind: .rest, duration: 300, at: start)
        XCTAssertEqual(session.kind, .rest)
        XCTAssertEqual(session.secondsLeft(at: start), 300)
        session.stop()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.deadline)
    }
}
