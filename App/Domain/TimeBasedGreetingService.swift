import Foundation
import Combine
import SwiftUI

/// Contract for calculating dynamic, time-of-day greetings across user devices and timezones.
public protocol TimeBasedGreetingProviding: Sendable {
    /// Returns the localized greeting for the given date and calendar.
    ///
    /// Rules:
    /// - 5:00 AM – 11:59 AM  -> "Good morning"
    /// - 12:00 PM – 4:59 PM  -> "Good afternoon"
    /// - 5:00 PM – 8:59 PM   -> "Good evening"
    /// - 9:00 PM – 4:59 AM   -> "Good night"
    func greeting(for date: Date, calendar: Calendar) -> String

    /// Formats a complete greeting string combining the time-of-day greeting and user's preferred name.
    /// Example: "Good morning, Alex"
    func fullGreeting(name: String, for date: Date, calendar: Calendar) -> String

    /// Calculates the exact Date when the greeting transitions to the next time-of-day state.
    /// Transitions occur at 5:00 AM, 12:00 PM, 5:00 PM, and 9:00 PM.
    func nextBoundaryDate(after date: Date, calendar: Calendar) -> Date

    /// Returns the greeting corresponding to the current system time and device calendar.
    var currentGreeting: String { get }
}

/// Robust, timezone-aware domain service that calculates greetings based on device local time.
public struct TimeBasedGreetingService: TimeBasedGreetingProviding, Sendable {
    public static let shared = TimeBasedGreetingService()

    public init() {}

    public func greeting(for date: Date, calendar: Calendar = .current) -> String {
        Self.greeting(for: date, calendar: calendar)
    }

    public func fullGreeting(name: String, for date: Date = Date(), calendar: Calendar = .current) -> String {
        let g = greeting(for: date, calendar: calendar)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? g : "\(g), \(trimmed)"
    }

    public func nextBoundaryDate(after date: Date, calendar: Calendar = .current) -> Date {
        Self.nextBoundaryDate(after: date, calendar: calendar)
    }

    public var currentGreeting: String {
        greeting(for: Date(), calendar: .current)
    }

    // MARK: - Deterministic Calculation Engine

    /// Returns the appropriate greeting string according to Daylight Money's local time guidelines.
    ///
    /// - 5:00 AM – 11:59 AM  -> "Good morning"
    /// - 12:00 PM – 4:59 PM  -> "Good afternoon"
    /// - 5:00 PM – 8:59 PM   -> "Good evening"
    /// - 9:00 PM – 4:59 AM   -> "Good night"
    public static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<21:
            return "Good evening"
        default:
            return "Good night"
        }
    }

    /// Determines the next boundary timestamp when the greeting phrase should transition.
    ///
    /// Boundary hours in 24h local time:
    /// - 05:00 (Good morning)
    /// - 12:00 (Good afternoon)
    /// - 17:00 (Good evening)
    /// - 21:00 (Good night)
    public static func nextBoundaryDate(after date: Date, calendar: Calendar = .current) -> Date {
        let boundaryHours = [5, 12, 17, 21]

        // Check each boundary hour later today
        for hour in boundaryHours {
            if let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date),
               boundary > date {
                return boundary
            }
        }

        // If all boundary hours for today have passed, the next transition is tomorrow at 5:00 AM
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
           let tomorrow5AM = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow) {
            return tomorrow5AM
        }

        // Absolute fallback: 1 hour in the future
        return date.addingTimeInterval(3600)
    }

    /// Returns the time interval in seconds until the next greeting transition.
    public static func timeIntervalUntilNextBoundary(after date: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        max(0, nextBoundaryDate(after: date, calendar: calendar).timeIntervalSince(date))
    }
}

// MARK: - Reactive Lifecycle Coordinator

/// Manages reactive updates for time-based greetings without constant polling.
///
/// Refreshes automatically on:
/// - Initial creation / view appearance
/// - App returning from background (`scenePhase == .active`)
/// - Device timezone changes (`NSSystemTimeZoneDidChangeNotification`)
/// - Device clock changes (`NSSystemClockDidChangeNotification`)
/// - Calendar day rolls over (`NSCalendarDayChangedNotification`)
/// - Time crosses a greeting transition boundary (scheduled precision sleep)
@MainActor
public final class TimeBasedGreetingCoordinator: ObservableObject {
    @Published public private(set) var greeting: String

    private let greetingService: TimeBasedGreetingProviding
    private var dateProvider: @Sendable () -> Date
    private var calendarProvider: @Sendable () -> Calendar
    private var scheduledTask: Task<Void, Never>? = nil

    public init(
        greetingService: TimeBasedGreetingProviding = TimeBasedGreetingService.shared,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { .current }
    ) {
        self.greetingService = greetingService
        self.dateProvider = dateProvider
        self.calendarProvider = calendarProvider
        self.greeting = greetingService.greeting(for: dateProvider(), calendar: calendarProvider())
    }

    deinit {
        scheduledTask?.cancel()
    }

    /// Formats the current greeting alongside the specified user name.
    public func fullGreeting(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? greeting : "\(greeting), \(trimmed)"
    }

    /// Refreshes the published greeting from current providers.
    public func refresh() {
        let now = dateProvider()
        let cal = calendarProvider()
        let newGreeting = greetingService.greeting(for: now, calendar: cal)
        if newGreeting != greeting {
            greeting = newGreeting
        }
    }

    /// Handles application foreground event.
    public func handleAppForeground() {
        refresh()
        scheduleNextBoundaryUpdate()
    }

    /// Handles application background event by pausing background tasks.
    public func handleAppBackground() {
        cancelBoundaryUpdate()
    }

    /// Handles system clock or timezone adjustments.
    public func handleSystemTimeOrTimezoneChange() {
        refresh()
        scheduleNextBoundaryUpdate()
    }

    /// Schedules a single precision sleep task that fires at the next greeting boundary.
    ///
    /// Avoids 1-second continuous polling by computing `nextBoundaryDate(after:)` and
    /// sleeping for the exact required duration + a 0.5s safety buffer.
    public func scheduleNextBoundaryUpdate() {
        scheduledTask?.cancel()

        let now = dateProvider()
        let cal = calendarProvider()
        let nextBoundary = greetingService.nextBoundaryDate(after: now, calendar: cal)
        let interval = nextBoundary.timeIntervalSince(now)
        // 0.5-second buffer ensures the clock has ticked into the new boundary minute
        let sleepDuration = max(0.5, interval + 0.5)

        scheduledTask = Task { [weak self] in
            let nanoseconds = UInt64(sleepDuration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return // Task was cancelled
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
            self?.scheduleNextBoundaryUpdate()
        }
    }

    /// Cancels any scheduled boundary task.
    public func cancelBoundaryUpdate() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    /// Testing injection helper to modify time and calendar sources deterministically.
    public func setProviders(
        dateProvider: @escaping @Sendable () -> Date,
        calendarProvider: @escaping @Sendable () -> Calendar
    ) {
        self.dateProvider = dateProvider
        self.calendarProvider = calendarProvider
    }
}
