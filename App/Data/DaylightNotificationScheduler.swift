import Foundation
import UserNotifications

/// Schedules and generates local Australian financial notifications from real calculated figures.
/// Respects user notification permissions, quiet hours, local Australian time zones, lock-screen
/// privacy masking, and deterministic request identifiers to prevent duplicate firing on restarts.
public enum DaylightNotificationScheduler {

    public struct GeneratedNotificationPayload: Equatable, Sendable {
        public let deterministicIdentifier: String
        public let title: String
        public let body: String
        public let lockScreenMaskedBody: String
        public let categoryTag: String
        public let targetSectionRawValue: String
    }

    /// Generates the daily evening allowance summary from actual calculated `DailyAllowanceSummary` data.
    /// Matches the exact format required:
    /// - Over allowance: "Your daily allowance was $114.28. You spent $128.40, which is $14.12 over your allowance."
    /// - Within allowance: "Your daily allowance is $114.28. You spent $24.30 today, leaving $89.98 safe to spend."
    /// - Zero spend today: "Your daily allowance is $114.28. No flexible spending recorded today—full allowance remaining."
    public static func buildDailyEveningSummary(
        tenantId: String,
        referenceDate: Date,
        timeZoneId: String,
        summary: DailyAllowanceSummary,
        preferences: NotificationPreferences
    ) -> GeneratedNotificationPayload {
        let dayKey = AustralianDateHelper.formatISODate(referenceDate, timeZoneId: timeZoneId)
        let id = "daylight.daily_summary.\(tenantId).\(dayKey)"

        let startingFormatted = AustralianMoneyFormatter.format(cents: summary.todaysStartingAllowanceCents)
        let spentFormatted = AustralianMoneyFormatter.format(cents: summary.flexibleSpentTodayCents)
        let remainingCents = summary.todaysRemainingAllowanceCents

        let fullBody: String
        if summary.flexibleSpentTodayCents == 0 {
            fullBody = "Your daily allowance is \(startingFormatted). No flexible spending recorded today—full allowance remaining."
        } else if remainingCents < 0 {
            let overByFormatted = AustralianMoneyFormatter.format(cents: abs(remainingCents))
            fullBody = "Your daily allowance was \(startingFormatted). You spent \(spentFormatted), which is \(overByFormatted) over your allowance."
        } else {
            let remainingFormatted = AustralianMoneyFormatter.format(cents: remainingCents)
            fullBody = "Your daily allowance is \(startingFormatted). You spent \(spentFormatted) today, leaving \(remainingFormatted) safe to spend."
        }

        let maskedBody = "Your daily spending summary is ready. Tap to view today's allowance in \(BrandConfig.appName)."

        return GeneratedNotificationPayload(
            deterministicIdentifier: id,
            title: "Daily Spending Summary",
            body: preferences.hideExactAmountsInPreviews ? maskedBody : fullBody,
            lockScreenMaskedBody: maskedBody,
            categoryTag: "daily_summary",
            targetSectionRawValue: "overview"
        )
    }

    /// Generates a category budget alert when a category reaches >= 85% or exceeds 100% of its period limit.
    public static func buildCategoryBudgetAlerts(
        tenantId: String,
        referenceDate: Date,
        timeZoneId: String,
        categoryProgress: [CategoryBudgetProgress],
        preferences: NotificationPreferences
    ) -> [GeneratedNotificationPayload] {
        guard preferences.budgetThresholdAlertsEnabled else { return [] }
        let dayKey = AustralianDateHelper.formatISODate(referenceDate, timeZoneId: timeZoneId)
        var alerts: [GeneratedNotificationPayload] = []

        for item in categoryProgress {
            if item.isOverBudget {
                let overCents = item.netSpentCents - item.budgetedCents
                let overFormatted = AustralianMoneyFormatter.format(cents: overCents)
                let spentFormatted = AustralianMoneyFormatter.format(cents: item.netSpentCents)
                let limitFormatted = AustralianMoneyFormatter.format(cents: item.budgetedCents)
                let fullBody = "\(item.category.displayName) is at \(spentFormatted) (\(overFormatted) over your \(limitFormatted) period budget)."
                let masked = "A category budget has exceeded its target for this pay period."
                alerts.append(
                    GeneratedNotificationPayload(
                        deterministicIdentifier: "daylight.budget_over.\(tenantId).\(item.category.rawValue).\(dayKey)",
                        title: "\(item.category.displayName) Over Budget",
                        body: preferences.hideExactAmountsInPreviews ? masked : fullBody,
                        lockScreenMaskedBody: masked,
                        categoryTag: "budget_alert",
                        targetSectionRawValue: "budgets"
                    )
                )
            } else if item.percentageUsed >= 0.85 {
                let pct = Int(round(item.percentageUsed * 100))
                let remFormatted = AustralianMoneyFormatter.format(cents: item.remainingCents)
                let fullBody = "You've used \(pct)% of your \(item.category.displayName) budget (\(remFormatted) remaining)."
                let masked = "A category budget is approaching its limit (\(pct)% used)."
                alerts.append(
                    GeneratedNotificationPayload(
                        deterministicIdentifier: "daylight.budget_warn.\(tenantId).\(item.category.rawValue).\(dayKey)",
                        title: "Approaching \(item.category.displayName) Limit",
                        body: preferences.hideExactAmountsInPreviews ? masked : fullBody,
                        lockScreenMaskedBody: masked,
                        categoryTag: "budget_alert",
                        targetSectionRawValue: "budgets"
                    )
                )
            }
        }
        return alerts
    }

    /// Generates upcoming bill reminders for bills due within the next 3 days.
    public static func buildUpcomingBillReminders(
        tenantId: String,
        referenceDate: Date,
        timeZoneId: String,
        recurringPredictions: [RecurringPaymentPrediction],
        preferences: NotificationPreferences
    ) -> [GeneratedNotificationPayload] {
        guard preferences.upcomingBillRemindersEnabled else { return [] }
        let cal = AustralianDateHelper.calendar(for: timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)
        guard let threeDaysOut = cal.date(byAdding: .day, value: 3, to: startOfToday) else { return [] }

        var reminders: [GeneratedNotificationPayload] = []
        for bill in recurringPredictions where !bill.isDismissed {
            if bill.nextExpectedDate >= startOfToday && bill.nextExpectedDate <= threeDaysOut {
                let dateFormatted = AustralianDateHelper.formatShortDate(bill.nextExpectedDate, timeZoneId: timeZoneId)
                let amountFormatted = AustralianMoneyFormatter.format(cents: bill.expectedAmountCents)
                let statusLabel = bill.isConfirmedByUser ? "Confirmed" : "Estimated"
                let fullBody = "\(statusLabel) \(bill.merchantName) payment of \(amountFormatted) is due on \(dateFormatted) via \(bill.paymentRail)."
                let masked = "An upcoming recurring bill (\(bill.merchantName)) is due on \(dateFormatted)."
                reminders.append(
                    GeneratedNotificationPayload(
                        deterministicIdentifier: "daylight.bill_due.\(tenantId).\(bill.id.uuidString).\(dateFormatted)",
                        title: "Upcoming Bill: \(bill.merchantName)",
                        body: preferences.hideExactAmountsInPreviews ? masked : fullBody,
                        lockScreenMaskedBody: masked,
                        categoryTag: "upcoming_bill",
                        targetSectionRawValue: "bills"
                    )
                )
            }
        }
        return reminders
    }

    /// Checks whether a given local hour falls inside quiet hours (default 22:00 – 07:00).
    public static func isWithinQuietHours(hour: Int, quietStartHour: Int = 22, quietEndHour: Int = 7) -> Bool {
        if quietStartHour > quietEndHour {
            return hour >= quietStartHour || hour < quietEndHour
        } else {
            return hour >= quietStartHour && hour < quietEndHour
        }
    }

    /// Adjusts the requested summary hour so it never schedules inside quiet hours (22:00 – 07:00).
    public static func effectiveSummaryHour(requestedHour: Int, quietStartHour: Int = 22, quietEndHour: Int = 7) -> Int {
        let clamped = min(max(requestedHour, 0), 23)
        if isWithinQuietHours(hour: clamped, quietStartHour: quietStartHour, quietEndHour: quietEndHour) {
            return 19 // Safe default 7:00 PM local time
        }
        return clamped
    }

    /// Requests OS notification authorization and schedules the daily summary notification in the user's Australian time zone.
    public static func syncScheduledOSNotifications(
        tenantId: String,
        referenceDate: Date,
        profile: UserProfile,
        summary: DailyAllowanceSummary,
        preferences: NotificationPreferences
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let refreshedSettings = await center.notificationSettings()
        guard refreshedSettings.authorizationStatus == .authorized || refreshedSettings.authorizationStatus == .provisional else {
            return false
        }

        // Remove any stale daily summary requests for this tenant before scheduling updated calculation
        let pending = await center.pendingNotificationRequests()
        let staleIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("daylight.daily_summary.\(tenantId)") }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        guard preferences.dailySummaryEnabled else {
            return true
        }

        let payload = buildDailyEveningSummary(
            tenantId: tenantId,
            referenceDate: referenceDate,
            timeZoneId: profile.timeZoneId,
            summary: summary,
            preferences: preferences
        )

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.userInfo = [
            "targetSection": payload.targetSectionRawValue,
            "tenantId": tenantId,
            "categoryTag": payload.categoryTag
        ]

        var dateComponents = DateComponents()
        dateComponents.timeZone = AustralianDateHelper.timeZone(for: profile.timeZoneId)
        dateComponents.hour = effectiveSummaryHour(requestedHour: preferences.dailySummaryHour)
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: payload.deterministicIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
