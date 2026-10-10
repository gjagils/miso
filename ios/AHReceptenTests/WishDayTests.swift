import Testing
@testable import AHRecepten

struct WishDayTests {
    @Test func weekdayMapping() {
        #expect(WishDayReminder.iosWeekday(fromServer: 6) == 1)  // zondag
        #expect(WishDayReminder.iosWeekday(fromServer: 0) == 2)  // maandag
        #expect(WishDayReminder.iosWeekday(fromServer: 5) == 7)  // zaterdag
    }

    @Test func messagesPerRole() {
        #expect(WishDayReminder.message(isKid: true, dayName: "zondag").body.contains("wilt eten"))
        #expect(WishDayReminder.message(isKid: false, dayName: "zondag").title == "Vandaag bestellen")
    }
}
