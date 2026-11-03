import Foundation
import os
import UserNotifications

/// Schedules and generates local Australian financial notifications from real calculated figures.
/// Respects user notification permissions, quiet hours, local Australian time zones, lock-screen
/// privacy masking, and deterministic request identifiers to prevent duplicate firing on restarts.
public enum DaylightNotificationScheduler {
    private static let logger = Logger(subsystem: "com.daylight.money", category: "notifications")

    public enum AuthorizationState: Equatable, Sendable {
        case notDetermined
        case authorized
        case provisional
        case denied
        case restricted
        case ephemeral
        case unavailable
    }

    public struct GeneratedNotificationPayload: Equatable, Sendable {
        public let deterministicIdentifier: String
        public let title: String
        public let body: String
        public let lockScreenMaskedBody: String
        public let categoryTag: String
        public let targetSectionRawValue: String
        public let relatedEntityID: String?
        public let eventIdentifier: String?

        public init(
            deterministicIdentifier: String,
            title: String,
            body: String,
            lockScreenMaskedBody: String,
            categoryTag: String,
            targetSectionRawValue: String,
            relatedEntityID: String? = nil,
            eventIdentifier: String? = nil
        ) {
            self.deterministicIdentifier = deterministicIdentifier
            self.title = title
            self.body = body
            self.lockScreenMaskedBody = lockScreenMaskedBody
            self.categoryTag = categoryTag
            self.targetSectionRawValue = targetSectionRawValue
            self.relatedEntityID = relatedEntityID
            self.eventIdentifier = eventIdentifier
        }
    }

    public static func authorizationState() async -> AuthorizationState {
        #if os(iOS)
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .ephemeral: return .ephemeral
        @unknown default: return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    public static func requestAuthorization() async throws -> AuthorizationState {
        let center = UNUserNotificationCenter.current()
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationState()
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
        if summary.totalFlexibleBudgetForPeriodCents == 0 &&
            summary.periodTakeHomeIncomeCents == 0 &&
            summary.flexibleSpentTodayCents == 0 {
            fullBody = "No spending recorded today ($0.00). Add your pay cycle or a transaction whenever you're ready to track your daily Safe-to-Spend."
        } else if summary.flexibleSpentTodayCents == 0 {
            fullBody = "Your daily allowance is \(startingFormatted). No spending today—full allowance remains."
        } else if summary.flexibleSpentTodayCents < 0 {
            let refundFormatted = AustralianMoneyFormatter.format(cents: abs(summary.flexibleSpentTodayCents))
            let remainingFormatted = AustralianMoneyFormatter.format(cents: max(0, remainingCents))
            fullBody = "Your daily allowance is \(startingFormatted). Net refunds of \(refundFormatted) today leave \(remainingFormatted) safe to spend."
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

    /// Convenience overload used by test harnesses and direct view models.
    public static func buildDailySummaryContent(
        summary: DailyAllowanceSummary,
        profile: UserProfile,
        preferences: NotificationPreferences? = nil
    ) -> GeneratedNotificationPayload {
        let resolvedPreferences = preferences ?? NotificationPreferences(
            dailySummaryEnabled: true,
            dailySummaryHour: 19,
            budgetThresholdAlertsEnabled: true,
            upcomingBillRemindersEnabled: true,
            paydayRemindersEnabled: true,
            recurringChangeAlertsEnabled: true,
            unusualSpendingAlertsEnabled: true,
            hideExactAmountsInPreviews: false
        )
        return buildDailyEveningSummary(
            tenantId: profile.tenantId,
            referenceDate: summary.periodStart,
            timeZoneId: profile.timeZoneId,
            summary: summary,
            preferences: resolvedPreferences
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
                        targetSectionRawValue: "budgets",
                        relatedEntityID: item.category.rawValue,
                        eventIdentifier: "over"
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
                        targetSectionRawValue: "budgets",
                        relatedEntityID: item.category.rawValue,
                        eventIdentifier: "threshold"
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
                let masked = "An upcoming recurring payment is due on \(dateFormatted)."
                let occurrenceKey = AustralianDateHelper.formatISODate(bill.nextExpectedDate, timeZoneId: timeZoneId)
                reminders.append(
                    GeneratedNotificationPayload(
                        deterministicIdentifier: "daylight.bill_due.\(tenantId).\(bill.id.uuidString).\(dateFormatted)",
                        title: "Upcoming Bill: \(bill.merchantName)",
                        body: preferences.hideExactAmountsInPreviews ? masked : fullBody,
                        lockScreenMaskedBody: masked,
                        categoryTag: "upcoming_bill",
                        targetSectionRawValue: "bills",
                        relatedEntityID: bill.id.uuidString,
                        eventIdentifier: occurrenceKey
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

    /// Removes all pending and delivered Daylight OS notifications across all tenants (e.g. on logout, reset, or workspace switch).
    public static func clearAllScheduledOSNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let pendingDaylightIds = pending.map(\.identifier).filter { $0.hasPrefix("daylight.") }
        if !pendingDaylightIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingDaylightIds)
        }
        let delivered = await center.deliveredNotifications()
        let deliveredDaylightIds = delivered.map { $0.request.identifier }.filter { $0.hasPrefix("daylight.") }
        if !deliveredDaylightIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredDaylightIds)
        }
    }

    /// Requests OS notification authorization and schedules non-repeating, date-specific daily summary notifications
    /// in the user's Australian time zone so yesterday's spend or another tenant's numbers never repeat on future zero-spend days.
    public static func syncScheduledOSNotifications(
        tenantId: String,
        referenceDate: Date,
        profile: UserProfile,
        summary: DailyAllowanceSummary,
        preferences: NotificationPreferences,
        accounts: [FinancialAccount] = [],
        transactions: [TransactionRecord] = [],
        fixedCommitments: [FixedCommitment] = [],
        categoryBudgets: [CategoryBudget] = [],
        recurringPredictions: [RecurringPaymentPrediction] = [],
        isDemoMode: Bool = false
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let tenantPendingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("daylight.") && $0.contains(".\(tenantId).") }

        guard !isDemoMode, preferences.notificationsEnabled else {
            if !tenantPendingIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: tenantPendingIDs)
            }
            return true
        }
        guard !Task.isCancelled else { return false }

        // Do not schedule empty notifications when no budget/income is configured and no spending occurred
        let hasConfiguredBudgetOrIncome = summary.totalFlexibleBudgetForPeriodCents > 0 || summary.periodTakeHomeIncomeCents > 0
        guard hasConfiguredBudgetOrIncome || summary.flexibleSpentTodayCents != 0 else {
            if !tenantPendingIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: tenantPendingIDs)
            }
            return true
        }

        let currentAuthorization = await authorizationState()
        guard currentAuthorization == .authorized || currentAuthorization == .provisional else {
            logger.info("Notification scheduling skipped because authorization is unavailable.")
            return false
        }

        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let tz = AustralianDateHelper.timeZone(for: profile.timeZoneId)
        let targetHour = effectiveSummaryHour(requestedHour: preferences.dailySummaryHour)
        let startOfToday = cal.startOfDay(for: referenceDate)

        var desiredRequests: [UNNotificationRequest] = []

        // Schedule date-specific (repeats: false) notifications for today (if before targetHour) and up to 7 upcoming days.
        // Because repeats is false and each future day computes its own fresh DailyAllowanceSummary, today's spending
        // is NEVER repeated on future days when spending is $0.00.
        let maxDayOffset = hasConfiguredBudgetOrIncome ? 7 : 0
        if preferences.dailySummaryEnabled {
            for dayOffset in 0...maxDayOffset {
            guard let targetDayStart = cal.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let fireDate = cal.date(bySettingHour: targetHour, minute: 0, second: 0, of: targetDayStart) else {
                continue
            }

            // Skip today's trigger if today's summary hour has already passed
            if fireDate <= referenceDate {
                continue
            }

            let daySummary: DailyAllowanceSummary
            if dayOffset == 0 {
                daySummary = summary
            } else {
                daySummary = FinancialCalculationEngine.calculateDailyAllowanceSummary(
                    referenceDate: fireDate,
                    profile: profile,
                    accounts: accounts,
                    transactions: transactions,
                    fixedCommitments: fixedCommitments,
                    categoryBudgets: categoryBudgets
                )
            }

            let payload = buildDailyEveningSummary(
                tenantId: tenantId,
                referenceDate: fireDate,
                timeZoneId: profile.timeZoneId,
                summary: daySummary,
                preferences: preferences
            )

            var dateComponents = cal.dateComponents([.year, .month, .day], from: fireDate)
            dateComponents.timeZone = tz
            dateComponents.hour = targetHour
            dateComponents.minute = 0
            dateComponents.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                desiredRequests.append(makeRequest(payload: payload, trigger: trigger, tenantId: tenantId))
            }
        }

        let budgetPayloads = preferences.budgetThresholdAlertsEnabled ? buildCategoryBudgetAlerts(
            tenantId: tenantId,
            referenceDate: referenceDate,
            timeZoneId: profile.timeZoneId,
            categoryProgress: categoryBudgets.isEmpty ? [] : FinancialCalculationEngine.calculateCategoryBudgetsProgress(
                referenceDate: referenceDate,
                profile: profile,
                transactions: transactions,
                categoryBudgets: categoryBudgets
            ),
            preferences: preferences
        ) : []
        if !budgetPayloads.isEmpty {
            let budgetDate = nextNotificationDate(
                after: referenceDate,
                hour: targetHour,
                calendar: cal
            )
            var components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: budgetDate)
            components.timeZone = tz
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            desiredRequests.append(contentsOf: budgetPayloads.map {
                makeRequest(payload: $0, trigger: trigger, tenantId: tenantId)
            })
        }

        let billPayloads = preferences.upcomingBillRemindersEnabled ? buildUpcomingBillReminders(
            tenantId: tenantId,
            referenceDate: referenceDate,
            timeZoneId: profile.timeZoneId,
            recurringPredictions: recurringPredictionsForScheduling(
                from: transactions,
                predictions: recurringPredictions
            ),
            preferences: preferences
        ) : []
        for payload in billPayloads {
            guard let bill = recurringPredictions.first(where: { $0.id.uuidString == payload.relatedEntityID }) else {
                continue
            }
            guard let fireDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.startOfDay(for: bill.nextExpectedDate)),
                  fireDate > referenceDate else {
                continue
            }
            var components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            components.timeZone = tz
            desiredRequests.append(makeRequest(
                payload: payload,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false),
                tenantId: tenantId
            ))
        }

        let existingDaylight = pending.filter { $0.identifier.hasPrefix("daylight.") && $0.identifier.contains(".\(tenantId).") }
        let desiredByID = Dictionary(uniqueKeysWithValues: desiredRequests.map { ($0.identifier, $0) })
        let obsolete = existingDaylight
            .filter { !desiredByID.keys.contains($0.identifier) }
            .map(\.identifier)
        if !obsolete.isEmpty {
            guard !Task.isCancelled else { return false }
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        do {
            for request in desiredRequests {
                guard !Task.isCancelled else { return false }
                if let existing = existingDaylight.first(where: { $0.identifier == request.identifier }),
                   existing.content.title == request.content.title,
                   existing.content.body == request.content.body {
                    continue
                }
                try await center.add(request)
            }
        } catch {
            logger.error("Notification scheduling failed for the current reconciliation.")
            return false
        }
        return true
    }

    private static func makeRequest(
        payload: GeneratedNotificationPayload,
        trigger: UNNotificationTrigger,
        tenantId: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        var userInfo: [String: String] = [
            "targetSection": payload.targetSectionRawValue,
            "tenantId": tenantId,
            "categoryTag": payload.categoryTag
        ]
        if let relatedEntityID = payload.relatedEntityID {
            userInfo["relatedEntityID"] = relatedEntityID
        }
        if let eventIdentifier = payload.eventIdentifier {
            userInfo["eventIdentifier"] = eventIdentifier
        }
        content.userInfo = userInfo
        return UNNotificationRequest(identifier: payload.deterministicIdentifier, content: content, trigger: trigger)
    }

    private static func nextNotificationDate(
        after date: Date,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? date
        return today > date
            ? today
            : (calendar.date(byAdding: .day, value: 1, to: start).flatMap {
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0)
            } ?? date)
    }

    private static func recurringPredictionsForScheduling(
        from transactions: [TransactionRecord],
        predictions: [RecurringPaymentPrediction]
    ) -> [RecurringPaymentPrediction] {
        predictions.filter { prediction in
            !prediction.isDismissed &&
            !transactions.contains {
                $0.occurredAt >= prediction.nextExpectedDate &&
                $0.merchantName.caseInsensitiveCompare(prediction.merchantName) == .orderedSame
            }
        }
    }
}
