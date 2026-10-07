import XCTest
@testable import PomodoroCore

final class FocusDurationTests: XCTestCase {
    func testMinutesAndSecondsIncludingRangeBoundaries() {
        let examples = ["25": 1500, "17:30": 1050, "00:30": 30, "0:01": 1,
                        "179:59": 10799, "180:00": 10800, " 05:09 ": 309]
        for (input, expected) in examples {
            XCTAssertEqual(FocusDuration.parse(input), expected, input)
        }
        XCTAssertEqual(FocusDuration.clock(30), "00:30")
        XCTAssertEqual(FocusDuration.clock(1050), "17:30")
    }

    func testInvalidFormatsAndDurationsAreRejected() {
        for input in ["", "0", "00:00", "25:60", "180:01", "181", "-1:00", "1.5",
                      "1:", ":30", "1:2:3", "25 minutes", "999999999999999999999999"] {
            XCTAssertNil(FocusDuration.parse(input), input)
        }
    }
}
