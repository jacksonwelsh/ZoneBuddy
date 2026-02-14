import Testing
@testable import ZoneBuddy

struct DurationFormattingTests {
    @Test
    func formatSeconds() {
        #expect(0.formattedDuration == "0:00")
        #expect(5.formattedDuration == "0:05")
        #expect(30.formattedDuration == "0:30")
    }

    @Test
    func formatMinutes() {
        #expect(60.formattedDuration == "1:00")
        #expect(90.formattedDuration == "1:30")
        #expect(300.formattedDuration == "5:00")
        #expect(605.formattedDuration == "10:05")
    }

    @Test
    func formatHours() {
        #expect(3600.formattedDuration == "1:00:00")
        #expect(3661.formattedDuration == "1:01:01")
        #expect(7200.formattedDuration == "2:00:00")
    }
}
