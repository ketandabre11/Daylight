import Foundation
import Testing
@testable import App

@Suite("Daylight Money — Dynamic Time-Based Greeting Tests")
@MainActor
struct DaylightMoneyTimeBasedGreetingTests {

    private func makeDate(
        year: Int = 2026,
        month: Int = 11,
        day: Int = 1,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZone: TimeZone = TimeZone(identifier: "Australia/Sydney")!
    ) -> (Date, Calendar) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = cal.date(from: components) else {
            fatalError("Could not create date for \(components)")
        }
        return (date, cal)
    }

    // MARK: - 1. Time Boundaries Specified in Requirements

    @Test("4:59 AM resolves to Good night")
    func test459AMResolvesToGoodNight() {
        let (date, cal) = makeDate(hour: 4, minute: 59)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good night")
    }

    @Test("5:00 AM resolves to Good morning")
    func test500AMResolvesToGoodMorning() {
        let (date, cal) = makeDate(hour: 5, minute: 0)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good morning")
    }

    @Test("11:59 AM resolves to Good morning")
    func test1159AMResolvesToGoodMorning() {
        let (date, cal) = makeDate(hour: 11, minute: 59)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good morning")
    }

    @Test("12:00 PM resolves to Good afternoon")
    func test1200PMResolvesToGoodAfternoon() {
        let (date, cal) = makeDate(hour: 12, minute: 0)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good afternoon")
    }

    @Test("4:59 PM resolves to Good afternoon")
    func test459PMResolvesToGoodAfternoon() {
        let (date, cal) = makeDate(hour: 16, minute: 59)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good afternoon")
    }

    @Test("5:00 PM resolves to Good evening")
    func test500PMResolvesToGoodEvening() {
        let (date, cal) = makeDate(hour: 17, minute: 0)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good evening")
    }

    @Test("8:59 PM resolves to Good evening")
    func test859PMResolvesToGoodEvening() {
        let (date, cal) = makeDate(hour: 20, minute: 59)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good evening")
    }

    @Test("9:00 PM resolves to Good night")
    func test900PMResolvesToGoodNight() {
        let (date, cal) = makeDate(hour: 21, minute: 0)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good night")
    }

    @Test("11:59 PM resolves to Good night")
    func test1159PMResolvesToGoodNight() {
        let (date, cal) = makeDate(hour: 23, minute: 59)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good night")
    }

    @Test("12:00 AM midnight resolves to Good night")
    func test1200AMMidnightResolvesToGoodNight() {
        let (date, cal) = makeDate(hour: 0, minute: 0)
        #expect(TimeBasedGreetingService.greeting(for: date, calendar: cal) == "Good night")
    }

    // MARK: - 2. User Name Integration

    @Test("Greeting displays alongside user preferred name")
    func testGreetingWithUserName() {
        let service = TimeBasedGreetingService.shared
        let (morningDate, cal) = makeDate(hour: 9, minute: 30)
        #expect(service.fullGreeting(name: "Alex", for: morningDate, calendar: cal) == "Good morning, Alex")

        let (afternoonDate, _) = makeDate(hour: 14, minute: 15)
        #expect(service.fullGreeting(name: "Alex", for: afternoonDate, calendar: cal) == "Good afternoon, Alex")

        let (eveningDate, _) = makeDate(hour: 18, minute: 45)
        #expect(service.fullGreeting(name: "Alex", for: eveningDate, calendar: cal) == "Good evening, Alex")

        let (nightDate, _) = makeDate(hour: 22, minute: 0)
        #expect(service.fullGreeting(name: "Alex", for: nightDate, calendar: cal) == "Good night, Alex")

        // Whitespace and empty name handling
        #expect(service.fullGreeting(name: "", for: morningDate, calendar: cal) == "Good morning")
        #expect(service.fullGreeting(name: "   ", for: morningDate, calendar: cal) == "Good morning")
    }

    // MARK: - 3. Timezone Changes & International Handling

    @Test("Timezone changes accurately reflect local time in different regions")
    func testTimezoneHandling() {
        // A single instant in UTC: 2026-11-01 13:00:00 UTC
        let utcInstant = Date(timeIntervalSince1970: 1793538000)

        // 1. Sydney (UTC+11 in November daylight time) -> 13:00 + 11 = 00:00 (Midnight, Nov 2) -> Good night
        var sydneyCal = Calendar(identifier: .gregorian)
        sydneyCal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        #expect(TimeBasedGreetingService.greeting(for: utcInstant, calendar: sydneyCal) == "Good night")

        // 2. Tokyo (UTC+9) -> 13:00 + 9 = 22:00 (10:00 PM, Nov 1) -> Good night
        var tokyoCal = Calendar(identifier: .gregorian)
        tokyoCal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(TimeBasedGreetingService.greeting(for: utcInstant, calendar: tokyoCal) == "Good night")

        // 3. London (UTC+0 in November GMT) -> 13:00 (1:00 PM, Nov 1) -> Good afternoon
        var londonCal = Calendar(identifier: .gregorian)
        londonCal.timeZone = TimeZone(identifier: "Europe/London")!
        #expect(TimeBasedGreetingService.greeting(for: utcInstant, calendar: londonCal) == "Good afternoon")

        // 4. New York (UTC-5 in standard time on Nov 1 after DST change) -> 08:00 (8:00 AM, Nov 1) -> Good morning
        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(TimeBasedGreetingService.greeting(for: utcInstant, calendar: nyCal) == "Good morning")

        // 5. Honolulu (UTC-10) -> 03:00 (3:00 AM, Nov 1) -> Good night
        var honoluluCal = Calendar(identifier: .gregorian)
        honoluluCal.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        #expect(TimeBasedGreetingService.greeting(for: utcInstant, calendar: honoluluCal) == "Good night")
    }

    @Test("Coordinator dynamically reflects device timezone adjustments")
    func testCoordinatorTimezoneChange() {
        let utcInstant = Date(timeIntervalSince1970: 1793538000) // 13:00 UTC
        var currentTz = TimeZone(identifier: "Europe/London")! // 1:00 PM -> Good afternoon

        let coordinator = TimeBasedGreetingCoordinator(
            greetingService: TimeBasedGreetingService.shared,
            dateProvider: { utcInstant },
            calendarProvider: {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = currentTz
                return cal
            }
        )

        #expect(coordinator.greeting == "Good afternoon")

        // Device changes timezone to New York (8:00 AM -> Good morning)
        currentTz = TimeZone(identifier: "America/New_York")!
        coordinator.handleSystemTimeOrTimezoneChange()
        #expect(coordinator.greeting == "Good morning")

        // Device changes timezone to Sydney (Midnight -> Good night)
        currentTz = TimeZone(identifier: "Australia/Sydney")!
        coordinator.handleSystemTimeOrTimezoneChange()
        #expect(coordinator.greeting == "Good night")
    }

    // MARK: - 4. Background-to-Foreground Refresh

    @Test("Coordinator refreshes greeting upon returning from background")
    func testBackgroundToForegroundRefresh() {
        var simulatedNow: Date
        var cal: Calendar
        (simulatedNow, cal) = makeDate(hour: 11, minute: 45) // Morning

        let coordinator = TimeBasedGreetingCoordinator(
            greetingService: TimeBasedGreetingService.shared,
            dateProvider: { simulatedNow },
            calendarProvider: { cal }
        )

        #expect(coordinator.greeting == "Good morning")

        // User backgrounds app, phone sits idle, resumes at 1:30 PM (Afternoon)
        coordinator.handleAppBackground()
        (simulatedNow, cal) = makeDate(hour: 13, minute: 30)
        coordinator.handleAppForeground()

        #expect(coordinator.greeting == "Good afternoon")
    }

    // MARK: - 5. Boundary Calculation & Crossing Across Thresholds

    @Test("Next boundary calculation correctly returns exact target timestamps")
    func testNextBoundaryCalculation() {
        let cal = Calendar(identifier: .gregorian)

        // 4:30 AM -> Next boundary is today at 5:00 AM
        let (d1, c1) = makeDate(hour: 4, minute: 30)
        let b1 = TimeBasedGreetingService.nextBoundaryDate(after: d1, calendar: c1)
        #expect(c1.component(.hour, from: b1) == 5)
        #expect(c1.component(.minute, from: b1) == 0)
        #expect(c1.component(.day, from: b1) == c1.component(.day, from: d1))

        // 7:15 AM -> Next boundary is today at 12:00 PM
        let (d2, c2) = makeDate(hour: 7, minute: 15)
        let b2 = TimeBasedGreetingService.nextBoundaryDate(after: d2, calendar: c2)
        #expect(c2.component(.hour, from: b2) == 12)
        #expect(c2.component(.minute, from: b2) == 0)

        // 1:45 PM -> Next boundary is today at 5:00 PM (17:00)
        let (d3, c3) = makeDate(hour: 13, minute: 45)
        let b3 = TimeBasedGreetingService.nextBoundaryDate(after: d3, calendar: c3)
        #expect(c3.component(.hour, from: b3) == 17)
        #expect(c3.component(.minute, from: b3) == 0)

        // 6:20 PM -> Next boundary is today at 9:00 PM (21:00)
        let (d4, c4) = makeDate(hour: 18, minute: 20)
        let b4 = TimeBasedGreetingService.nextBoundaryDate(after: d4, calendar: c4)
        #expect(c4.component(.hour, from: b4) == 21)
        #expect(c4.component(.minute, from: b4) == 0)

        // 10:15 PM -> Next boundary is TOMORROW at 5:00 AM
        let (d5, c5) = makeDate(day: 1, hour: 22, minute: 15)
        let b5 = TimeBasedGreetingService.nextBoundaryDate(after: d5, calendar: c5)
        #expect(c5.component(.hour, from: b5) == 5)
        #expect(c5.component(.minute, from: b5) == 0)
        #expect(c5.component(.day, from: b5) == 2)
    }

    @Test("App remaining open across boundary updates greeting seamlessly without restart")
    func testAppRemainingOpenAcrossGreetingBoundary() {
        var currentTime: Date
        var cal: Calendar
        (currentTime, cal) = makeDate(hour: 11, minute: 59, second: 55)

        let coordinator = TimeBasedGreetingCoordinator(
            greetingService: TimeBasedGreetingService.shared,
            dateProvider: { currentTime },
            calendarProvider: { cal }
        )

        #expect(coordinator.greeting == "Good morning")

        // 10 seconds elapse: clock ticks from 11:59:55 AM to 12:00:05 PM
        (currentTime, cal) = makeDate(hour: 12, minute: 0, second: 5)
        coordinator.refresh()

        #expect(coordinator.greeting == "Good afternoon")
        #expect(coordinator.fullGreeting(for: "Alex") == "Good afternoon, Alex")

        // Later: clock ticks from 4:59:58 PM to 5:00:02 PM
        (currentTime, cal) = makeDate(hour: 17, minute: 0, second: 2)
        coordinator.refresh()

        #expect(coordinator.greeting == "Good evening")

        // Later: clock ticks from 8:59:59 PM to 9:00:01 PM
        (currentTime, cal) = makeDate(hour: 21, minute: 0, second: 1)
        coordinator.refresh()

        #expect(coordinator.greeting == "Good night")
    }

    // MARK: - 6. Alternative Calendar Systems

    @Test("Greetings function properly across varied calendar systems without string parsing errors")
    func testAlternativeCalendars() {
        let (baseDate, _) = makeDate(hour: 14, minute: 30)

        // Japanese Calendar
        let japaneseCal = Calendar(identifier: .japanese)
        #expect(TimeBasedGreetingService.greeting(for: baseDate, calendar: japaneseCal) == "Good afternoon")

        // Buddhist Calendar
        let buddhistCal = Calendar(identifier: .buddhist)
        #expect(TimeBasedGreetingService.greeting(for: baseDate, calendar: buddhistCal) == "Good afternoon")
    }
}
