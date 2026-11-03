import Foundation
import CryptoKit

public enum FinancialCalculationEngine {
    public static let currentCalculationVersion: Int = 3

    private static func isIncludedTransaction(_ transaction: TransactionRecord) -> Bool {
        transaction.status == .posted || transaction.status == .refunded
    }

    public static func isVerifiedIncome(_ transaction: TransactionRecord) -> Bool {
        !transaction.excludeFromBudget
            && isIncludedTransaction(transaction)
            && transaction.kind == .income
            && transaction.direction == .credit
            && transaction.classificationConfidence >= 0.70
    }

    public static func isVerifiedRefund(_ transaction: TransactionRecord) -> Bool {
        transaction.linkedOriginalTransactionId != nil
            || (transaction.source == .manualEntry && transaction.classificationConfidence >= 0.70)
    }

    public static func isValidDirection(_ direction: TransactionDirection, for kind: TransactionKind) -> Bool {
        switch kind {
        case .income, .creditCardRepayment, .refund, .reversal:
            return direction == .credit
        case .expense, .creditCardPurchase, .cashWithdrawal, .feeOrInterest:
            return direction == .debit
        case .ownAccountTransfer:
            return true
        }
    }

    // MARK: - 1. Active Period Bounds Calculation

    /// Computes a calendar-accurate monthly boundary shifted by `monthOffset` months from `anchorStartOfDay` in `calendar`,
    /// clamping to the last valid day of shorter months (e.g. Jan 31 -> Feb 28/29) and restoring the original anchor day in
    /// subsequent longer months (e.g. Mar 31) with zero anchor drift across multi-month sequences.
    public static func monthlyAnchorBoundaryDate(
        anchorStartOfDay: Date,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date {
        if monthOffset == 0 {
            return calendar.startOfDay(for: anchorStartOfDay)
        }
        let anchorComps = calendar.dateComponents([.year, .month, .day], from: anchorStartOfDay)
        let anchorDay = max(1, anchorComps.day ?? 1)
        var firstOfAnchorMonthComps = DateComponents()
        firstOfAnchorMonthComps.year = anchorComps.year
        firstOfAnchorMonthComps.month = anchorComps.month
        firstOfAnchorMonthComps.day = 1
        let firstOfAnchorMonth = calendar.date(from: firstOfAnchorMonthComps) ?? anchorStartOfDay
        let targetMonthFirst = calendar.date(byAdding: .month, value: monthOffset, to: firstOfAnchorMonth) ?? firstOfAnchorMonth
        let maxDayInTargetMonth = calendar.range(of: .day, in: .month, for: targetMonthFirst)?.count ?? 28
        let clampedDay = min(anchorDay, maxDayInTargetMonth)

        let targetYM = calendar.dateComponents([.year, .month], from: targetMonthFirst)
        var targetComps = DateComponents()
        targetComps.year = targetYM.year
        targetComps.month = targetYM.month
        targetComps.day = clampedDay
        return calendar.startOfDay(for: calendar.date(from: targetComps) ?? targetMonthFirst)
    }

    /// Computes exact half-open `[startDate, endDate)` boundaries for the active budget period in the user's configured
    /// Australian time zone (`Australia/Sydney` by default), using Foundation `Calendar` & `DateComponents` with zero 30-day drift.
    public static func currentPeriodHalfOpenBounds(
        referenceDate: Date,
        profile: UserProfile
    ) -> (startDate: Date, endDate: Date, totalDays: Int, elapsedDays: Int, remainingDays: Int) {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)

        if profile.preferredBudgetingMethod == .monthlyFlexible {
            let comps = cal.dateComponents([.year, .month], from: startOfToday)
            let startOfMonth = cal.startOfDay(for: cal.date(from: comps) ?? startOfToday)
            let nextMonthStart = cal.startOfDay(
                for: cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfToday
            )
            let totalDays = max(1, cal.dateComponents([.day], from: startOfMonth, to: nextMonthStart).day ?? 28)
            let elapsed = min(totalDays - 1, max(0, cal.dateComponents([.day], from: startOfMonth, to: startOfToday).day ?? 0))
            let remaining = max(1, totalDays - elapsed)
            return (startOfMonth, nextMonthStart, totalDays, elapsed, remaining)
        }

        let anchorNextPay = cal.startOfDay(for: profile.nextPayDate)

        if profile.payFrequency == .monthly {
            let anchorYM = cal.dateComponents([.year, .month], from: anchorNextPay)
            let todayYM = cal.dateComponents([.year, .month], from: startOfToday)
            var endOffset = ((todayYM.year ?? 0) - (anchorYM.year ?? 0)) * 12
                + ((todayYM.month ?? 0) - (anchorYM.month ?? 0))

            while monthlyAnchorBoundaryDate(anchorStartOfDay: anchorNextPay, monthOffset: endOffset, calendar: cal) <= startOfToday {
                endOffset += 1
            }
            while monthlyAnchorBoundaryDate(anchorStartOfDay: anchorNextPay, monthOffset: endOffset - 1, calendar: cal) > startOfToday {
                endOffset -= 1
            }

            let periodStart = monthlyAnchorBoundaryDate(anchorStartOfDay: anchorNextPay, monthOffset: endOffset - 1, calendar: cal)
            let periodEndExclusive = monthlyAnchorBoundaryDate(anchorStartOfDay: anchorNextPay, monthOffset: endOffset, calendar: cal)
            let totalDays = max(1, cal.dateComponents([.day], from: periodStart, to: periodEndExclusive).day ?? 28)
            let elapsed = min(totalDays - 1, max(0, cal.dateComponents([.day], from: periodStart, to: startOfToday).day ?? 0))
            let remaining = max(1, totalDays - elapsed)
            return (periodStart, periodEndExclusive, totalDays, elapsed, remaining)
        }

        let stepDays = max(1, profile.payFrequency.fixedCycleDays ?? profile.payFrequency.nominalPeriodDays)
        let dayDelta = cal.dateComponents([.day], from: anchorNextPay, to: startOfToday).day ?? 0
        let periodIndex = dayDelta >= 0
            ? (dayDelta / stepDays)
            : ((dayDelta - (stepDays - 1)) / stepDays)
        let periodStart = cal.startOfDay(
            for: cal.date(byAdding: .day, value: periodIndex * stepDays, to: anchorNextPay) ?? startOfToday
        )
        let periodEndExclusive = cal.startOfDay(
            for: cal.date(byAdding: .day, value: (periodIndex + 1) * stepDays, to: anchorNextPay) ?? startOfToday
        )
        let totalDays = max(1, cal.dateComponents([.day], from: periodStart, to: periodEndExclusive).day ?? stepDays)
        let elapsed = min(totalDays - 1, max(0, cal.dateComponents([.day], from: periodStart, to: startOfToday).day ?? 0))
        let remaining = max(1, totalDays - elapsed)
        return (periodStart, periodEndExclusive, totalDays, elapsed, remaining)
    }

    /// Returns the number of calendar days until the next scheduled payday.
    /// This is intentionally independent from the active budget period, which may
    /// be a calendar month and therefore have a different remaining-day count.
    public static func daysUntilNextPayDate(
        referenceDate: Date,
        profile: UserProfile
    ) -> Int {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let today = cal.startOfDay(for: referenceDate)
        var nextPay = cal.startOfDay(for: profile.nextPayDate)

        if profile.payFrequency == .monthly {
            let todayComponents = cal.dateComponents([.year, .month], from: today)
            let payComponents = cal.dateComponents([.year, .month], from: nextPay)
            var monthOffset = ((todayComponents.year ?? 0) - (payComponents.year ?? 0)) * 12
                + ((todayComponents.month ?? 0) - (payComponents.month ?? 0))
            nextPay = monthlyAnchorBoundaryDate(
                anchorStartOfDay: nextPay,
                monthOffset: monthOffset,
                calendar: cal
            )
            while nextPay <= today {
                monthOffset += 1
                nextPay = monthlyAnchorBoundaryDate(
                    anchorStartOfDay: profile.nextPayDate,
                    monthOffset: monthOffset,
                    calendar: cal
                )
            }
        } else {
            let stepDays = max(1, profile.payFrequency.fixedCycleDays ?? profile.payFrequency.nominalPeriodDays)
            while nextPay <= today {
                nextPay = cal.date(byAdding: .day, value: stepDays, to: nextPay) ?? nextPay
            }
        }

        return max(0, cal.dateComponents([.day], from: today, to: nextPay).day ?? 0)
    }

    /// Returns whether `timestamp` belongs to the half-open interval `[startDate, endDate)`.
    public static func isTimestampInHalfOpenPeriod(
        _ timestamp: Date,
        startDate: Date,
        endDate: Date
    ) -> Bool {
        timestamp >= startDate && timestamp < endDate
    }

    /// Computes the start and inclusive end-of-period calendar day in the user's configured Australian time zone.
    public static func currentPeriodBounds(
        referenceDate: Date,
        profile: UserProfile
    ) -> (start: Date, end: Date, totalDays: Int, elapsedDays: Int, remainingDays: Int) {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let halfOpen = currentPeriodHalfOpenBounds(referenceDate: referenceDate, profile: profile)
        let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: halfOpen.endDate) ?? halfOpen.startDate
        return (halfOpen.startDate, inclusiveEnd, halfOpen.totalDays, halfOpen.elapsedDays, halfOpen.remainingDays)
    }

    private static let defaultFixedCategorySet: Set<AustralianCategory> = Set(
        AustralianCategory.allCases.filter(\.isDefaultFixedCommitment)
    )

    /// Returns the union of default fixed-commitment categories and any categories explicitly configured as confirmed FixedCommitments.
    /// Ensures user-added commitments in non-default categories (e.g. BNPL, Transport Pass, Healthcare Plan) are reconciled and never double-counted.
    public static func effectiveFixedCommitmentCategories(
        fixedCommitments: [FixedCommitment],
        archivedCategories: Set<AustralianCategory> = []
    ) -> Set<AustralianCategory> {
        var categories = defaultFixedCategorySet
        for commitment in fixedCommitments where commitment.isConfirmed {
            categories.insert(commitment.category)
        }
        categories.subtract(archivedCategories)
        return categories
    }

    /// Returns the active calculation target frequency for cross-period budget normalisation.
    public static func activeCalculationTargetFrequency(for profile: UserProfile) -> PayFrequency {
        profile.preferredBudgetingMethod == .monthlyFlexible ? .monthly : profile.payFrequency
    }

    /// Returns the exact stored display figures for a `CategoryBudget` in its own configured `periodType`.
    /// Never converts or scales display limits to the user's profile pay-cycle frequency.
    public static func displayAmountForCategoryBudget(
        _ budget: CategoryBudget
    ) -> (
        baseLimitCents: MoneyCents,
        rolloverAppliedCents: MoneyCents,
        effectiveLimitCents: MoneyCents,
        periodType: PayFrequency
    ) {
        let base = max(0, budget.limitCents)
        let rollover = budget.rolloverEnabled ? budget.rolloverBalanceCents : 0
        let effective = max(0, base + rollover)
        return (base, rollover, effective, budget.periodType)
    }

    /// Deterministic integer-cent calculation conversion across pay/budget frequencies using Australian standard
    /// annualised calendar equivalence (52 weeks = 26 fortnights = 12 calendar months = 13 four-week cycles)
    /// and nearest-cent half-up rounding. Never uses a synthetic 30-day month.
    public static func normalizedAmountForCalculation(
        amountCents: MoneyCents,
        from sourceFrequency: PayFrequency,
        to targetFrequency: PayFrequency
    ) -> MoneyCents {
        guard amountCents != 0 else { return 0 }
        if sourceFrequency == targetFrequency {
            return amountCents
        }
        if amountCents == .min { return .min }
        let sign: MoneyCents = amountCents >= 0 ? 1 : -1
        let absAmount = abs(amountCents)
        let sourceUnits = Int64(sourceFrequency.annualCyclesCount)
        let targetUnits = Int64(targetFrequency.annualCyclesCount)
        let (scaledAmount, overflow) = absAmount.multipliedReportingOverflow(by: sourceUnits)
        guard !overflow else { return sign == 1 ? .max : .min }
        let (roundedAmount, roundingOverflow) = scaledAmount.addingReportingOverflow(targetUnits / 2)
        guard !roundingOverflow else { return sign == 1 ? .max : .min }
        let converted = roundedAmount / targetUnits
        return sign * converted
    }

    /// Normalizes an integer-cent monetary amount from `sourceFrequency` to the active calculation frequency.
    /// Retained for call-site compatibility; delegates to `normalizedAmountForCalculation` without 30-day monthly assumptions.
    public static func normalizedAmountForPeriod(
        amountCents: MoneyCents,
        sourceFrequency: PayFrequency,
        isMonthlyCalendarMode: Bool,
        periodDays: Int,
        targetFrequency: PayFrequency? = nil
    ) -> MoneyCents {
        let resolvedTarget: PayFrequency
        if let targetFrequency {
            resolvedTarget = targetFrequency
        } else if isMonthlyCalendarMode {
            resolvedTarget = .monthly
        } else if periodDays == 7 {
            resolvedTarget = .weekly
        } else if periodDays == 14 {
            resolvedTarget = .fortnightly
        } else if periodDays == 28 && sourceFrequency == .irregular {
            resolvedTarget = .irregular
        } else {
            resolvedTarget = .monthly
        }
        return normalizedAmountForCalculation(
            amountCents: amountCents,
            from: sourceFrequency,
            to: resolvedTarget
        )
    }

    /// Computes the required per-period contribution (rounded UP to the nearest cent so target is guaranteed to be met on time) for a savings goal.
    public static func suggestedContributionPerPeriodCents(
        for goal: SavingsGoal,
        referenceDate: Date,
        profile: UserProfile
    ) -> MoneyCents? {
        let remainingCents = max(0, goal.targetAmountCents - goal.currentSavedCents)
        guard let targetDate = goal.targetDate, remainingCents > 0 else { return nil }

        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)
        let startOfTarget = cal.startOfDay(for: targetDate)

        if startOfTarget <= startOfToday {
            return remainingCents
        }

        let cyclesRemaining: Int
        if profile.preferredBudgetingMethod == .monthlyFlexible {
            let todayComps = cal.dateComponents([.year, .month], from: startOfToday)
            let targetComps = cal.dateComponents([.year, .month], from: startOfTarget)
            let monthsDiff = ((targetComps.year ?? 0) - (todayComps.year ?? 0)) * 12
                + ((targetComps.month ?? 0) - (todayComps.month ?? 0))
            cyclesRemaining = max(1, monthsDiff)
        } else if profile.payFrequency == .monthly {
            let anchorStart = cal.startOfDay(for: profile.nextPayDate)
            let anchorYM = cal.dateComponents([.year, .month], from: anchorStart)
            let todayYM = cal.dateComponents([.year, .month], from: startOfToday)
            var offset = ((todayYM.year ?? 0) - (anchorYM.year ?? 0)) * 12
                + ((todayYM.month ?? 0) - (anchorYM.month ?? 0))
            while monthlyAnchorBoundaryDate(anchorStartOfDay: anchorStart, monthOffset: offset, calendar: cal) <= startOfToday {
                offset += 1
            }
            while monthlyAnchorBoundaryDate(anchorStartOfDay: anchorStart, monthOffset: offset - 1, calendar: cal) > startOfToday {
                offset -= 1
            }
            var paydaysBeforeOrOnTarget = 0
            while paydaysBeforeOrOnTarget < 10_000 {
                let payday = monthlyAnchorBoundaryDate(
                    anchorStartOfDay: anchorStart,
                    monthOffset: offset + paydaysBeforeOrOnTarget,
                    calendar: cal
                )
                if payday <= startOfTarget {
                    paydaysBeforeOrOnTarget += 1
                } else {
                    break
                }
            }
            cyclesRemaining = max(1, paydaysBeforeOrOnTarget)
        } else {
            let cycleDays = max(1, profile.payFrequency.fixedCycleDays ?? profile.payFrequency.nominalPeriodDays)
            var nextPay = cal.startOfDay(for: profile.nextPayDate)
            while nextPay <= startOfToday {
                nextPay = cal.date(byAdding: .day, value: cycleDays, to: nextPay)
                    ?? nextPay.addingTimeInterval(Double(cycleDays) * 86400)
            }
            var paydaysBeforeOrOnTarget = 0
            var cursor = nextPay
            while cursor <= startOfTarget && paydaysBeforeOrOnTarget < 10_000 {
                paydaysBeforeOrOnTarget += 1
                cursor = cal.date(byAdding: .day, value: cycleDays, to: cursor)
                    ?? cursor.addingTimeInterval(Double(cycleDays) * 86400)
            }
            if paydaysBeforeOrOnTarget > 0 {
                cyclesRemaining = paydaysBeforeOrOnTarget
            } else {
                let daysLeft = max(1, cal.dateComponents([.day], from: startOfToday, to: startOfTarget).day ?? 1)
                cyclesRemaining = max(1, (daysLeft + cycleDays - 1) / cycleDays)
            }
        }

        // Ceiling integer division guarantees `cyclesRemaining * perCycle >= remainingCents`
        return (remainingCents + Int64(cyclesRemaining) - 1) / Int64(cyclesRemaining)
    }

    // MARK: - 2. Transaction Eligibility & Net Spend Rules

    /// Determines whether a transaction represents net flexible spending, fixed bill payment, income, or non-consumption transfer.
    /// - Own-account transfers (`ownAccountTransfer`) and credit card bill repayments (`creditCardRepayment`) NEVER count as consumption.
    /// - Credit card purchases (`creditCardPurchase`) count as consumption when the purchase is made.
    /// - Refunds (`refund`) and reversals (`reversal`) offset spending in their category rather than inflating income.
    public static func netSpendContributionCents(
        for transaction: TransactionRecord,
        categoryFilter: AustralianCategory? = nil,
        includeFixedCategories: Bool = true,
        excludedFixedCategories: Set<AustralianCategory>? = nil
    ) -> MoneyCents {
        guard !transaction.excludeFromBudget else { return 0 }
        guard isIncludedTransaction(transaction) else { return 0 }
        let fixedSet = excludedFixedCategories ?? defaultFixedCategorySet

        switch transaction.kind {
        case .ownAccountTransfer, .creditCardRepayment, .income:
            return 0
        case .refund, .reversal:
            guard isVerifiedRefund(transaction) else { return 0 }
            if !transaction.splits.isEmpty {
                return transaction.splits.reduce(0) { acc, split in
                    guard !split.excludeFromBudget else { return acc }
                    if let filter = categoryFilter, split.category != filter { return acc }
                    if !includeFixedCategories && fixedSet.contains(split.category) { return acc }
                    return acc - split.amountCents
                }
            }
            if let filter = categoryFilter, transaction.category != filter { return 0 }
            if !includeFixedCategories && fixedSet.contains(transaction.category) { return 0 }
            return -transaction.amountCents

        case .expense, .creditCardPurchase, .cashWithdrawal, .feeOrInterest:
            let sign: MoneyCents = (transaction.direction == .debit) ? 1 : -1
            if !transaction.splits.isEmpty {
                return transaction.splits.reduce(0) { acc, split in
                    guard !split.excludeFromBudget else { return acc }
                    if let filter = categoryFilter, split.category != filter { return acc }
                    if !includeFixedCategories && fixedSet.contains(split.category) { return acc }
                    return acc + (split.amountCents * sign)
                }
            }
            if let filter = categoryFilter, transaction.category != filter { return 0 }
            if !includeFixedCategories && fixedSet.contains(transaction.category) { return 0 }
            return transaction.amountCents * sign
        }
    }

    // MARK: - 3. Daily Safe-to-Spend & Period Budget Calculation

    public struct FixedReconciliationResult: Equatable, Sendable {
        public let effectiveTotalFixedForPeriodCents: MoneyCents
        public let unpaidFixedRemainingCents: MoneyCents
        public let reconciliationNotices: [FixedReconciliationNotice]
        public let flexibleSpilloverFromUnlinkedCategoriesCents: MoneyCents

        public init(
            effectiveTotalFixedForPeriodCents: MoneyCents,
            unpaidFixedRemainingCents: MoneyCents,
            reconciliationNotices: [FixedReconciliationNotice],
            flexibleSpilloverFromUnlinkedCategoriesCents: MoneyCents
        ) {
            self.effectiveTotalFixedForPeriodCents = effectiveTotalFixedForPeriodCents
            self.unpaidFixedRemainingCents = unpaidFixedRemainingCents
            self.reconciliationNotices = reconciliationNotices
            self.flexibleSpilloverFromUnlinkedCategoriesCents = flexibleSpilloverFromUnlinkedCategoriesCents
        }
    }

    /// Single authoritative fixed-expense reconciliation mechanism across fixed commitments, category limits,
    /// and transactions. Guarantees:
    /// 1. Fixed category limits are accounted for in reserved fixed expenses even without a separate fixed commitment.
    /// 2. Matching obligations are never counted twice.
    /// 3. Paid bills reconcile against their commitments without leaking across categories or double-deducting in flexible spending.
    /// 4. Inactive/archived commitments/categories are ignored.
    public static func reconcileFixedCommitmentsAndCategoryLimits(
        fixedCommitments: [FixedCommitment],
        categoryBudgets: [CategoryBudget],
        periodTransactions: [TransactionRecord],
        effectiveFixedCategories: Set<AustralianCategory>,
        activeTargetFrequency: PayFrequency,
        archivedCategories: Set<AustralianCategory> = []
    ) -> FixedReconciliationResult {
        let activeConfirmedCommitments = fixedCommitments.filter {
            $0.isConfirmed && !archivedCategories.contains($0.category)
        }
        let confirmedCommitmentById = Dictionary(uniqueKeysWithValues: activeConfirmedCommitments.map { ($0.id, $0) })
        var reservedByCommitmentId: [UUID: MoneyCents] = [:]
        var commitmentsByCategory: [AustralianCategory: [FixedCommitment]] = [:]
        for commitment in activeConfirmedCommitments {
            let normReserved = max(
                0,
                normalizedAmountForCalculation(
                    amountCents: commitment.amountCents,
                    from: commitment.frequency,
                    to: activeTargetFrequency
                )
            )
            reservedByCommitmentId[commitment.id] = normReserved
            commitmentsByCategory[commitment.category, default: []].append(commitment)
        }

        let activeBudgets = categoryBudgets.filter { !archivedCategories.contains($0.category) }
        let budgetsByCategory = Dictionary(grouping: activeBudgets, by: \.category)

        var explicitlyLinkedNetByCommitmentId: [UUID: MoneyCents] = [:]
        var unlinkedFixedNetByCategory: [AustralianCategory: MoneyCents] = [:]

        for tx in periodTransactions {
            guard !tx.excludeFromBudget, isIncludedTransaction(tx) else { continue }
            if (tx.kind == .refund || tx.kind == .reversal) && !isVerifiedRefund(tx) {
                continue
            }
            if let linkedId = tx.linkedFixedCommitmentId, let linkedCommitment = confirmedCommitmentById[linkedId] {
                let netContribution = netSpendContributionCents(
                    for: tx,
                    categoryFilter: nil,
                    includeFixedCategories: true,
                    excludedFixedCategories: effectiveFixedCategories
                )
                explicitlyLinkedNetByCommitmentId[linkedCommitment.id, default: 0] += netContribution
                continue
            }

            if !tx.splits.isEmpty {
                for split in tx.splits where !split.excludeFromBudget && effectiveFixedCategories.contains(split.category) {
                    let delta: MoneyCents
                    switch tx.kind {
                    case .ownAccountTransfer, .creditCardRepayment, .income:
                        delta = 0
                    case .refund, .reversal:
                        delta = -split.amountCents
                    case .expense, .creditCardPurchase, .cashWithdrawal, .feeOrInterest:
                        let sign: MoneyCents = (tx.direction == .debit) ? 1 : -1
                        delta = split.amountCents * sign
                    }
                    if delta != 0 {
                        unlinkedFixedNetByCategory[split.category, default: 0] += delta
                    }
                }
            } else if effectiveFixedCategories.contains(tx.category) {
                let netCat = netSpendContributionCents(
                    for: tx,
                    categoryFilter: tx.category,
                    includeFixedCategories: true,
                    excludedFixedCategories: effectiveFixedCategories
                )
                if netCat != 0 {
                    unlinkedFixedNetByCategory[tx.category, default: 0] += netCat
                }
            }
        }

        var effectiveTotalFixedForPeriodCents: MoneyCents = 0
        var unpaidFixedRemainingCents: MoneyCents = 0
        var reconciliationNotices: [FixedReconciliationNotice] = []
        var flexibleSpilloverFromUnlinkedCategoriesCents: MoneyCents = 0

        let allRelevantFixedCategories = effectiveFixedCategories
            .union(Set(commitmentsByCategory.keys))
            .union(Set(unlinkedFixedNetByCategory.keys))
            .sorted { $0.rawValue < $1.rawValue }

        for category in allRelevantFixedCategories {
            let catCommitments = commitmentsByCategory[category] ?? []
            if !catCommitments.isEmpty {
                var remainingPoolCents = unlinkedFixedNetByCategory[category] ?? 0

                if catCommitments.count > 1 && remainingPoolCents > 0 {
                    let catReservedSum = catCommitments.reduce(MoneyCents(0)) { $0 + (reservedByCommitmentId[$1.id] ?? 0) }
                    reconciliationNotices.append(
                        FixedReconciliationNotice(
                            kind: .unmatchedTransactionInFixedCategory,
                            category: category,
                            message: "Multiple fixed commitments exist in \(category.displayName). Link transactions directly to a specific commitment if an expense is unrelated to a scheduled bill.",
                            reservedCents: catReservedSum
                        )
                    )
                }

                for (idx, commitment) in catCommitments.enumerated() {
                    let reserved = reservedByCommitmentId[commitment.id] ?? 0
                    let explicitPaid = explicitlyLinkedNetByCommitmentId[commitment.id] ?? 0
                    let stillUnreconciled = max(0, reserved - max(0, explicitPaid))

                    let allocatedFromPool: MoneyCents
                    if idx == catCommitments.count - 1 {
                        allocatedFromPool = remainingPoolCents
                        remainingPoolCents = 0
                    } else if remainingPoolCents >= 0 {
                        let applied = min(remainingPoolCents, stillUnreconciled)
                        allocatedFromPool = applied
                        remainingPoolCents -= applied
                    } else {
                        allocatedFromPool = remainingPoolCents
                        remainingPoolCents = 0
                    }

                    let netPaidForCommitment = max(0, explicitPaid + allocatedFromPool)
                    let unpaidForCommitment = max(0, reserved - netPaidForCommitment)
                    let effectiveForCommitment = max(reserved, netPaidForCommitment)

                    unpaidFixedRemainingCents += unpaidForCommitment
                    effectiveTotalFixedForPeriodCents += effectiveForCommitment
                }
            } else {
                // Fixed category with NO confirmed FixedCommitment records:
                // Check if the user has configured an active CategoryBudget limit for this fixed category.
                let catBudgets = budgetsByCategory[category] ?? []
                let catBudgetReserved = catBudgets.reduce(MoneyCents(0)) { sum, budget in
                    let normalized = normalizedAmountForCalculation(
                        amountCents: max(0, budget.limitCents),
                        from: budget.periodType,
                        to: activeTargetFrequency
                    )
                    let rollover = budget.rolloverEnabled
                        ? normalizedAmountForCalculation(
                            amountCents: budget.rolloverBalanceCents,
                            from: budget.periodType,
                            to: activeTargetFrequency
                        )
                        : 0
                    return sum + max(0, normalized + rollover)
                }

                let unlinkedNet = unlinkedFixedNetByCategory[category] ?? 0

                if catBudgetReserved > 0 {
                    // Category limit without separate fixed commitment: account for in reserved fixed expenses
                    if unlinkedNet >= 0 {
                        let unpaidRemaining = max(0, catBudgetReserved - unlinkedNet)
                        let effective = max(catBudgetReserved, unlinkedNet)
                        unpaidFixedRemainingCents += unpaidRemaining
                        effectiveTotalFixedForPeriodCents += effective
                    } else {
                        // Net credit / refund in category
                        unpaidFixedRemainingCents += catBudgetReserved
                        effectiveTotalFixedForPeriodCents += catBudgetReserved
                        flexibleSpilloverFromUnlinkedCategoriesCents += unlinkedNet
                    }

                    reconciliationNotices.append(
                        FixedReconciliationNotice(
                            kind: .categoryLimitWithoutFixedCommitment,
                            category: category,
                            message: "\(category.displayName) limit of \(AustralianMoneyFormatter.format(cents: catBudgetReserved)) is accounted for in fixed expenses because no separate fixed commitment was created.",
                            reservedCents: catBudgetReserved
                        )
                    )
                } else {
                    // No fixed commitment and no category budget:
                    let unlinkedPaid = max(0, unlinkedNet)
                    if unlinkedPaid > 0 {
                        effectiveTotalFixedForPeriodCents += unlinkedPaid
                    } else if unlinkedNet < 0 {
                        flexibleSpilloverFromUnlinkedCategoriesCents += unlinkedNet
                    }
                }
            }
        }

        // Check if any CategoryBudget exists in a fixed category with confirmed commitments without an explicit link
        for budget in activeBudgets where effectiveFixedCategories.contains(budget.category) {
            if let linkedId = budget.linkedFixedCommitmentId, confirmedCommitmentById[linkedId] != nil {
                continue
            }
            if !(commitmentsByCategory[budget.category] ?? []).isEmpty {
                let catReservedSum = (commitmentsByCategory[budget.category] ?? []).reduce(MoneyCents(0)) { $0 + (reservedByCommitmentId[$1.id] ?? 0) }
                reconciliationNotices.append(
                    FixedReconciliationNotice(
                        kind: .mismatchedCommitmentAndCategoryLimit,
                        category: budget.category,
                        message: "\(budget.category.displayName) has both a category tracking limit and a reserved fixed commitment. Safe-to-Spend reserves the fixed commitment once and never double-subtracts the category limit.",
                        reservedCents: catReservedSum
                    )
                )
            }
        }

        return FixedReconciliationResult(
            effectiveTotalFixedForPeriodCents: effectiveTotalFixedForPeriodCents,
            unpaidFixedRemainingCents: unpaidFixedRemainingCents,
            reconciliationNotices: reconciliationNotices,
            flexibleSpilloverFromUnlinkedCategoriesCents: flexibleSpilloverFromUnlinkedCategoriesCents
        )
    }

    public static func calculateDailyAllowanceSummary(
        referenceDate: Date,
        profile: UserProfile,
        accounts: [FinancialAccount],
        transactions: [TransactionRecord],
        fixedCommitments: [FixedCommitment],
        categoryBudgets: [CategoryBudget],
        savingsGoals: [SavingsGoal] = [],
        archivedCategories: Set<AustralianCategory> = []
    ) -> DailyAllowanceSummary {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let halfOpenBounds = currentPeriodHalfOpenBounds(referenceDate: referenceDate, profile: profile)
        let bounds = currentPeriodBounds(referenceDate: referenceDate, profile: profile)
        let startOfToday = cal.startOfDay(for: referenceDate)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate

        // 1. Account balances (clearly separated from budget figures)
        let activeAccounts = accounts.filter { $0.connectionStatus != .disconnected }
        let everydayAvailableCents = activeAccounts
            .filter { $0.accountType == .everydayTransaction }
            .reduce(MoneyCents(0)) { $0 + $1.availableBalanceCents }

        let totalLiquidCashCents = activeAccounts
            .filter { $0.accountType.isAssetAccount && $0.includeInSafeToSpendCash }
            .reduce(MoneyCents(0)) { $0 + $1.availableBalanceCents }

        let totalDebtCents = activeAccounts
            .filter { !$0.accountType.isAssetAccount }
            .reduce(MoneyCents(0)) { $0 + abs($1.currentBalanceCents) }

        // 2. Normalize income, fixed commitments, and savings to the active period length
        let effectiveFixedCategories = effectiveFixedCommitmentCategories(
            fixedCommitments: fixedCommitments,
            archivedCategories: archivedCategories
        )

        // Filter transactions occurring within the active half-open period [startDate, endDate)
        let periodEndExclusive = halfOpenBounds.endDate
        let periodTransactions = transactions.filter { tx in
            isTimestampInHalfOpenPeriod(
                tx.occurredAt,
                startDate: halfOpenBounds.startDate,
                endDate: periodEndExclusive
            )
        }

        // Actual posted/pending income transactions recorded in the active period (used when profile pay is unconfigured)
        let actualRecordedIncomeCents: MoneyCents = periodTransactions.reduce(0) { sum, tx in
            guard isVerifiedIncome(tx) else { return sum }
            return sum + abs(tx.amountCents)
        }

        let activeTargetFrequency = activeCalculationTargetFrequency(for: profile)

        let periodIncomeCents: MoneyCents = {
            if profile.typicalTakeHomePayCents > 0 {
                return normalizedAmountForCalculation(
                    amountCents: profile.typicalTakeHomePayCents,
                    from: profile.payFrequency,
                    to: activeTargetFrequency
                )
            }
            return actualRecordedIncomeCents
        }()

        let configuredPeriodSavingsCents = max(
            0,
            normalizedAmountForCalculation(
                amountCents: profile.savingsTargetPerPeriodCents,
                from: profile.payFrequency,
                to: activeTargetFrequency
            )
        )

        // 2b. Per-commitment & per-category fixed commitment reconciliation (prevents double-counting AND cross-category masking)
        let fixedReconciliation = reconcileFixedCommitmentsAndCategoryLimits(
            fixedCommitments: fixedCommitments,
            categoryBudgets: categoryBudgets,
            periodTransactions: periodTransactions,
            effectiveFixedCategories: effectiveFixedCategories,
            activeTargetFrequency: activeTargetFrequency,
            archivedCategories: archivedCategories
        )
        let effectiveTotalFixedForPeriodCents = fixedReconciliation.effectiveTotalFixedForPeriodCents
        let unpaidFixedRemainingCents = fixedReconciliation.unpaidFixedRemainingCents
        let reconciliationNotices = fixedReconciliation.reconciliationNotices
        let flexibleSpilloverFromUnlinkedCategoriesCents = fixedReconciliation.flexibleSpilloverFromUnlinkedCategoriesCents

        let availableCashAfterCommitmentsCents = everydayAvailableCents - unpaidFixedRemainingCents

        // In Savings-First mode, if no manual per-period savings target is set, automatically lock away required active savings-goal schedules first
        let periodSavingsCents: MoneyCents = {
            if profile.preferredBudgetingMethod == .savingsFirst && configuredPeriodSavingsCents == 0 && !savingsGoals.isEmpty {
                let goalsRequiredSum = savingsGoals.reduce(MoneyCents(0)) { acc, goal in
                    acc + (suggestedContributionPerPeriodCents(for: goal, referenceDate: referenceDate, profile: profile) ?? 0)
                }
                let maxLockableAfterFixed = max(0, periodIncomeCents - effectiveTotalFixedForPeriodCents)
                return min(maxLockableAfterFixed, goalsRequiredSum)
            }
            return configuredPeriodSavingsCents
        }()

        // 3. Determine total flexible budget for the period according to the user's selected BudgetingMethod
        let activeBudgets = categoryBudgets.filter { !archivedCategories.contains($0.category) }
        let derivedPoolCents = max(0, periodIncomeCents - effectiveTotalFixedForPeriodCents - periodSavingsCents)
        let flexibleCategoryEnvelopeSumCents: MoneyCents = activeBudgets
            .filter { !effectiveFixedCategories.contains($0.category) }
            .reduce(MoneyCents(0)) { acc, budget in
                let normalizedBase = normalizedAmountForCalculation(
                    amountCents: max(0, budget.limitCents),
                    from: budget.periodType,
                    to: activeTargetFrequency
                )
                let rollover = budget.rolloverEnabled
                    ? normalizedAmountForCalculation(
                        amountCents: budget.rolloverBalanceCents,
                        from: budget.periodType,
                        to: activeTargetFrequency
                    )
                    : 0
                return acc + max(0, normalizedBase + rollover)
            }

        let totalFlexibleBudgetCents: MoneyCents = {
            switch profile.preferredBudgetingMethod {
            case .custom:
                if let customCap = profile.customFlexibleCapCents {
                    return min(max(0, customCap), derivedPoolCents)
                }
                return derivedPoolCents
            case .categorySpecific:
                return flexibleCategoryEnvelopeSumCents > 0 ? flexibleCategoryEnvelopeSumCents : derivedPoolCents
            case .simpleDailyAllowance, .monthlyFlexible, .payCycle, .savingsFirst:
                return derivedPoolCents
            }
        }()

        // Baseline daily allowance across full period
        let baselineDailyCents = totalFlexibleBudgetCents / Int64(max(1, bounds.totalDays))

        // 4. Calculate flexible spending prior to today vs today vs future-dated entries within period
        var spentPriorToTodayCents: MoneyCents = 0
        var spentTodayCents: MoneyCents = 0
        var scheduledFutureFlexibleCents: MoneyCents = 0

        for tx in periodTransactions {
            let netFlexible = netSpendContributionCents(
                for: tx,
                categoryFilter: nil,
                includeFixedCategories: false,
                excludedFixedCategories: effectiveFixedCategories
            )
            guard netFlexible != 0 else { continue }
            if tx.occurredAt >= startOfToday && tx.occurredAt < endOfToday {
                spentTodayCents += netFlexible
            } else if tx.occurredAt < startOfToday {
                spentPriorToTodayCents += netFlexible
            } else {
                // Future-dated transactions within the current pay period reserve period budget without inflating today's spend
                scheduledFutureFlexibleCents += netFlexible
            }
        }

        spentPriorToTodayCents = max(0, spentPriorToTodayCents)
        let reservedFutureFlexibleCents = max(0, scheduledFutureFlexibleCents)
        let totalFlexibleSpentCents = max(0, spentPriorToTodayCents + spentTodayCents + reservedFutureFlexibleCents)
        let remainingFlexibleForPeriodCents = totalFlexibleBudgetCents - totalFlexibleSpentCents

        // Dynamic Safe-to-Spend at the start of today:
        // Take the flexible budget remaining at the start of today and divide across remaining days (including today).
        let budgetAtStartOfTodayCents = max(0, totalFlexibleBudgetCents - spentPriorToTodayCents - reservedFutureFlexibleCents)
        let todaysStartingAllowanceCents = budgetAtStartOfTodayCents / Int64(max(1, bounds.remainingDays))
        let todaysRemainingAllowanceCents = todaysStartingAllowanceCents - spentTodayCents

        // Forecast end-of-period flexible spend using rounded run-rate on incurred spend + scheduled future spend (no integer pre-division truncation)
        let activeDaysSoFar = max(1, bounds.elapsedDays + 1)
        let incurredFlexibleSoFarCents = max(0, spentPriorToTodayCents + spentTodayCents)
        let extrapolatedIncurredCents = (incurredFlexibleSoFarCents * Int64(bounds.totalDays) + Int64(activeDaysSoFar / 2)) / Int64(activeDaysSoFar)
        let forecastFlexibleCents = max(totalFlexibleSpentCents, extrapolatedIncurredCents + reservedFutureFlexibleCents)

        let step2And3: [String] = {
            if profile.preferredBudgetingMethod == .savingsFirst {
                return [
                    "2. Less Locked-In Savings Target First: -\(AustralianMoneyFormatter.format(cents: periodSavingsCents))",
                    "3. Less Fixed Commitments & Bills (paid & scheduled, never double-counted): -\(AustralianMoneyFormatter.format(cents: effectiveTotalFixedForPeriodCents))"
                ]
            } else {
                return [
                    "2. Less Fixed Commitments & Bills (paid & scheduled, never double-counted): -\(AustralianMoneyFormatter.format(cents: effectiveTotalFixedForPeriodCents))",
                    "3. Less Planned Savings Target: -\(AustralianMoneyFormatter.format(cents: periodSavingsCents))"
                ]
            }
        }()

        let step4Line: String = {
            switch profile.preferredBudgetingMethod {
            case .custom where profile.customFlexibleCapCents != nil:
                return "4. Custom Period Flexible Cap Applied (Derived Cash-Flow Pool \(AustralianMoneyFormatter.format(cents: derivedPoolCents))): \(AustralianMoneyFormatter.format(cents: totalFlexibleBudgetCents)) (Baseline \(AustralianMoneyFormatter.format(cents: baselineDailyCents))/day)"
            case .categorySpecific where flexibleCategoryEnvelopeSumCents > 0:
                return "4. Category Envelopes Total Applied (Derived Cash-Flow Pool \(AustralianMoneyFormatter.format(cents: derivedPoolCents))): \(AustralianMoneyFormatter.format(cents: totalFlexibleBudgetCents)) (Baseline \(AustralianMoneyFormatter.format(cents: baselineDailyCents))/day)"
            default:
                return "4. Total Flexible Budget for Period: \(AustralianMoneyFormatter.format(cents: totalFlexibleBudgetCents)) (Baseline \(AustralianMoneyFormatter.format(cents: baselineDailyCents))/day)"
            }
        }()

        var steps: [String] = [
            "1. Period Take-Home Income (\(bounds.totalDays) days): \(AustralianMoneyFormatter.format(cents: periodIncomeCents))"
        ]
        steps.append(contentsOf: step2And3)
        steps.append(step4Line)
        steps.append("5. Less Flexible Spending Before Today: -\(AustralianMoneyFormatter.format(cents: spentPriorToTodayCents))")
        if reservedFutureFlexibleCents > 0 {
            steps.append("5b. Less Scheduled Future Flexible Spend in Period: -\(AustralianMoneyFormatter.format(cents: reservedFutureFlexibleCents))")
        }
        steps.append("6. Today's Opening Safe Allowance (\(AustralianMoneyFormatter.format(cents: budgetAtStartOfTodayCents)) ÷ \(bounds.remainingDays) days left): \(AustralianMoneyFormatter.format(cents: todaysStartingAllowanceCents))")
        steps.append("7. Less Today's Eligible Flexible Spending: -\(AustralianMoneyFormatter.format(cents: spentTodayCents))")
        steps.append("8. Today's Remaining Safe-to-Spend Allowance: \(AustralianMoneyFormatter.format(cents: todaysRemainingAllowanceCents))")

        return DailyAllowanceSummary(
            periodStart: bounds.start,
            periodEnd: bounds.end,
            totalDaysInPeriod: bounds.totalDays,
            elapsedDaysInPeriod: bounds.elapsedDays,
            remainingDaysInPeriod: bounds.remainingDays,
            everydayAvailableBankBalanceCents: everydayAvailableCents,
            totalLiquidCashAcrossAccountsCents: totalLiquidCashCents,
            totalCreditCardAndDebtBalanceCents: totalDebtCents,
            periodTakeHomeIncomeCents: periodIncomeCents,
            totalFixedCommitmentsForPeriodCents: effectiveTotalFixedForPeriodCents,
            unpaidFixedCommitmentsRemainingCents: unpaidFixedRemainingCents,
            plannedSavingsForPeriodCents: periodSavingsCents,
            availableCashAfterCommitmentsCents: availableCashAfterCommitmentsCents,
            totalFlexibleBudgetForPeriodCents: totalFlexibleBudgetCents,
            baselineDailyAllowanceCents: baselineDailyCents,
            flexibleSpentPriorToTodayCents: spentPriorToTodayCents,
            flexibleSpentTodayCents: spentTodayCents,
            totalFlexibleSpentInPeriodCents: totalFlexibleSpentCents,
            remainingFlexibleBudgetForPeriodCents: remainingFlexibleForPeriodCents,
            todaysStartingAllowanceCents: todaysStartingAllowanceCents,
            todaysRemainingAllowanceCents: todaysRemainingAllowanceCents,
            forecastEndOfPeriodFlexibleSpendCents: forecastFlexibleCents,
            calculationSteps: steps,
            reconciliationNotices: reconciliationNotices,
            budgetingMethodUsed: profile.preferredBudgetingMethod,
            calculationVersion: currentCalculationVersion
        )
    }

    // MARK: - 4. Category Budget Period Bounds & Progress Calculation

    /// Computes exact half-open `[start, endExclusive)` and inclusive `[start, end]` period bounds for a category budget's
    /// own configured `periodType` in the user's Australian time zone (`Australia/Sydney` by default), independent of
    /// whether the user's profile pay-cycle frequency differs.
    public static func categoryBudgetPeriodBounds(
        for periodType: PayFrequency,
        referenceDate: Date,
        profile: UserProfile
    ) -> (start: Date, end: Date, endExclusive: Date, totalDays: Int, elapsedDays: Int, remainingDays: Int) {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)

        if let stepDays = periodType.fixedCycleDays {
            let safeStep = max(1, stepDays)
            let anchorStartOfDay = cal.startOfDay(for: profile.nextPayDate)
            let dayDelta = cal.dateComponents([.day], from: anchorStartOfDay, to: startOfToday).day ?? 0
            let periodIndex = dayDelta >= 0
                ? (dayDelta / safeStep)
                : ((dayDelta - (safeStep - 1)) / safeStep)
            let periodStart = cal.date(byAdding: .day, value: periodIndex * safeStep, to: anchorStartOfDay) ?? startOfToday
            let periodEndExclusive = cal.date(byAdding: .day, value: (periodIndex + 1) * safeStep, to: anchorStartOfDay)
                ?? cal.date(byAdding: .day, value: safeStep, to: periodStart)
                ?? periodStart
            let periodEnd = cal.date(byAdding: .day, value: -1, to: periodEndExclusive) ?? periodStart
            let totalDays = max(1, cal.dateComponents([.day], from: periodStart, to: periodEndExclusive).day ?? safeStep)
            let elapsedRaw = cal.dateComponents([.day], from: periodStart, to: startOfToday).day ?? 0
            let elapsedDays = min(max(0, elapsedRaw), totalDays - 1)
            let remainingDays = max(1, totalDays - elapsedDays)
            return (periodStart, periodEnd, periodEndExclusive, totalDays, elapsedDays, remainingDays)
        } else {
            // `.monthly` category budget: if user is on a monthly pay-cycle (non-calendar mode), align with their monthly pay cycle;
            // otherwise use the exact calendar month [startOfMonth, nextMonthStart) in `profile.timeZoneId`.
            if profile.preferredBudgetingMethod != .monthlyFlexible && profile.payFrequency == .monthly {
                let halfOpen = currentPeriodHalfOpenBounds(referenceDate: referenceDate, profile: profile)
                let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: halfOpen.endDate) ?? halfOpen.startDate
                return (halfOpen.startDate, inclusiveEnd, halfOpen.endDate, halfOpen.totalDays, halfOpen.elapsedDays, halfOpen.remainingDays)
            }
            let comps = cal.dateComponents([.year, .month], from: startOfToday)
            let startOfMonth = cal.date(from: comps) ?? startOfToday
            let nextMonthStart = cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfToday
            let endOfMonth = cal.date(byAdding: .day, value: -1, to: nextMonthStart) ?? startOfToday
            let totalDays = max(1, cal.dateComponents([.day], from: startOfMonth, to: nextMonthStart).day ?? 28)
            let elapsedRaw = cal.dateComponents([.day], from: startOfMonth, to: startOfToday).day ?? 0
            let elapsedDays = min(max(0, elapsedRaw), totalDays - 1)
            let remainingDays = max(1, totalDays - elapsedDays)
            return (startOfMonth, endOfMonth, nextMonthStart, totalDays, elapsedDays, remainingDays)
        }
    }

    /// Computes progress for a single `CategoryBudget` within its own configured `periodType`, keeping display limits
    /// strictly in the category's chosen period while exposing `normalizedActivePeriodLimitCents` separately for cross-period math.
    public static func categoryBudgetProgress(
        for budget: CategoryBudget,
        referenceDate: Date,
        profile: UserProfile,
        transactions: [TransactionRecord]
    ) -> CategoryBudgetProgress {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate
        let catBounds = categoryBudgetPeriodBounds(
            for: budget.periodType,
            referenceDate: referenceDate,
            profile: profile
        )
        let display = displayAmountForCategoryBudget(budget)
        let activeTargetFrequency = activeCalculationTargetFrequency(for: profile)
        let normalizedBaseForActivePeriod = max(
            0,
            normalizedAmountForCalculation(
                amountCents: display.baseLimitCents,
                from: budget.periodType,
                to: activeTargetFrequency
            )
        )
        let normalizedRolloverForActivePeriod = budget.rolloverEnabled
            ? normalizedAmountForCalculation(
                amountCents: display.rolloverAppliedCents,
                from: budget.periodType,
                to: activeTargetFrequency
            )
            : 0
        let normalizedActiveEffectiveLimit = max(0, normalizedBaseForActivePeriod + normalizedRolloverForActivePeriod)

        let periodTransactions = transactions.filter {
            $0.occurredAt >= catBounds.start && $0.occurredAt < catBounds.endExclusive
        }
        let elapsedDays = max(1, catBounds.elapsedDays + 1)

        var incurredSpentSoFar: MoneyCents = 0
        var futureScheduledSpent: MoneyCents = 0
        var matchingTxs: [TransactionRecord] = []

        for tx in periodTransactions {
            let contribution = netSpendContributionCents(
                for: tx,
                categoryFilter: budget.category,
                includeFixedCategories: true
            )
            if contribution != 0 {
                if tx.occurredAt < endOfToday {
                    incurredSpentSoFar += contribution
                } else {
                    futureScheduledSpent += contribution
                }
                matchingTxs.append(tx)
            }
        }

        let clampedIncurred = max(0, incurredSpentSoFar)
        let clampedFuture = max(0, futureScheduledSpent)
        let netSpent = max(0, incurredSpentSoFar + futureScheduledSpent)
        let remaining = display.effectiveLimitCents - netSpent
        let ratio: Double = {
            if display.effectiveLimitCents > 0 {
                return Double(netSpent) / Double(display.effectiveLimitCents)
            }
            return netSpent > 0 ? 1.0 : 0.0
        }()
        let extrapolatedIncurred = (clampedIncurred * Int64(catBounds.totalDays) + Int64(elapsedDays / 2)) / Int64(elapsedDays)
        let projected = max(netSpent, extrapolatedIncurred + clampedFuture)

        return CategoryBudgetProgress(
            category: budget.category,
            budgetedCents: display.effectiveLimitCents,
            baseLimitCents: display.baseLimitCents,
            rolloverAppliedCents: display.rolloverAppliedCents,
            sourceLimitCents: display.baseLimitCents,
            sourcePeriodType: display.periodType,
            normalizedActivePeriodLimitCents: normalizedActiveEffectiveLimit,
            periodStart: catBounds.start,
            periodEnd: catBounds.end,
            netSpentCents: netSpent,
            remainingCents: remaining,
            percentageUsed: ratio,
            projectedEndOfPeriodCents: projected,
            isOverBudget: netSpent > display.effectiveLimitCents,
            recentTransactions: matchingTxs.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    public static func calculateCategoryBudgetsProgress(
        referenceDate: Date,
        profile: UserProfile,
        transactions: [TransactionRecord],
        categoryBudgets: [CategoryBudget],
        archivedCategories: Set<AustralianCategory> = []
    ) -> [CategoryBudgetProgress] {
        categoryBudgets
            .filter { !archivedCategories.contains($0.category) }
            .map { budget in
                categoryBudgetProgress(
                    for: budget,
                    referenceDate: referenceDate,
                    profile: profile,
                    transactions: transactions
                )
            }
            .sorted { $0.percentageUsed > $1.percentageUsed }
    }

    // MARK: - 5. Australian Merchant & Category Classifier

    public struct ClassificationResult: Equatable, Sendable {
        public let normalizedMerchant: String
        public let category: AustralianCategory
        public let kind: TransactionKind
        public let paymentRail: String?
        public let confidence: Double
    }

    /// Classifies an Australian transaction description using user merchant rules first, then curated Australian merchant patterns.
    /// Never classifies purely from an amount or ambiguous generic text; returns low confidence (< 0.5) when uncertain.
    public static func classifyAustralianTransaction(
        rawDescription: String,
        direction: TransactionDirection,
        isCreditCardAccount: Bool,
        userMerchantRules: [MerchantRule] = []
    ) -> ClassificationResult {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        // Detect Australian payment rail from description
        let detectedRail: String? = {
            if upper.contains("OSKO") || upper.contains("PAYID") || upper.contains("NPP") {
                return "Osko / PayID"
            } else if upper.contains("BPAY") {
                return "BPAY"
            } else if upper.contains("DIRECT DEBIT") || upper.contains("DDR") {
                return "Direct Debit"
            } else if upper.contains("EFTPOS") || upper.contains("VISA") || upper.contains("MASTERCARD") || upper.contains("APPLE PAY") {
                return "eftpos / Card"
            }
            return nil
        }()

        // 1. Check user-defined merchant rules first
        let isTransferDescription = upper.contains("INTERNAL TRANSFER")
            || upper.contains("TRANSFER TO OFFSET")
            || upper.contains("TRANSFER TO SAVINGS")
            || upper.contains("TRANSFER FROM SAVINGS")
            || upper.contains("OWN ACCOUNT")
        let isRefundDescription = direction == .credit
            && (upper.contains("REFUND") || upper.contains("REBATE") || upper.contains("MEDICARE") || upper.contains("REVERSAL"))

        if !isTransferDescription && !isRefundDescription {
            for rule in userMerchantRules {
                guard upper.localizedCaseInsensitiveContains(rule.matchSubstring) else { continue }
                let kind: TransactionKind = (direction == .credit) ? .income : (isCreditCardAccount ? .creditCardPurchase : .expense)
                return ClassificationResult(
                    normalizedMerchant: rule.normalizedMerchantName,
                    category: rule.assignedCategory,
                    kind: kind,
                    paymentRail: detectedRail,
                    confidence: 0.98
                )
            }
        }

        // 2. Check internal transfers & credit card repayments
        if upper.contains("INTERNAL TRANSFER") || upper.contains("TRANSFER TO OFFSET") || upper.contains("TRANSFER TO SAVINGS") || upper.contains("TRANSFER FROM SAVINGS") || upper.contains("OWN ACCOUNT") {
            return ClassificationResult(
                normalizedMerchant: "Own Account Transfer",
                category: .ownAccountTransfer,
                kind: .ownAccountTransfer,
                paymentRail: detectedRail ?? "Internal Transfer",
                confidence: 0.96
            )
        }

        if upper.contains("CREDIT CARD REPAYMENT") || upper.contains("CC REPAYMENT") || upper.contains("CARD AUTOPAY") {
            return ClassificationResult(
                normalizedMerchant: "Credit Card Repayment",
                category: .creditCardRepayment,
                kind: .creditCardRepayment,
                paymentRail: detectedRail ?? "BPAY / Internal",
                confidence: 0.96
            )
        }

        // 3. Check refunds & rebates
        if direction == .credit && (upper.contains("REFUND") || upper.contains("REBATE") || upper.contains("MEDICARE") || upper.contains("REVERSAL")) {
            let isMedicare = upper.contains("MEDICARE")
            return ClassificationResult(
                normalizedMerchant: isMedicare ? "Medicare Australia Rebate" : trimmed,
                category: isMedicare ? .healthcareMedicare : .shoppingRetail,
                kind: upper.contains("REVERSAL") ? .reversal : .refund,
                paymentRail: detectedRail,
                confidence: 0.92
            )
        }

        // 4. Check Australian income sources
        if direction == .credit {
            if upper.contains("SALARY") || upper.contains("PAYROLL") || upper.contains("WAGES") || upper.contains("PTY LTD") {
                return ClassificationResult(
                    normalizedMerchant: "Employer Payroll",
                    category: .salaryWagesIncome,
                    kind: .income,
                    paymentRail: detectedRail ?? "Direct Credit",
                    confidence: 0.94
                )
            }
            if upper.contains("SERVICES AUSTRALIA") || upper.contains("CENTRELINK") || upper.contains("FAMILY TAX") {
                return ClassificationResult(
                    normalizedMerchant: "Services Australia",
                    category: .governmentPayments,
                    kind: .income,
                    paymentRail: "Direct Credit",
                    confidence: 0.95
                )
            }
        }

        let defaultPurchaseKind: TransactionKind = isCreditCardAccount ? .creditCardPurchase : .expense

        // 5. Curated Australian merchants & institutions
        let rules: [(keywords: [String], merchant: String, category: AustralianCategory, confidence: Double)] = [
            (["WOOLWORTHS", "METRO WOOLWORTHS"], "Woolworths", .groceries, 0.96),
            (["COLES", "COLES SUPERMARKET"], "Coles", .groceries, 0.96),
            (["ALDI STORES", "ALDI "], "ALDI", .groceries, 0.95),
            (["IGA ", "HARRIS FARM"], "Harris Farm / IGA", .groceries, 0.93),
            (["TRANSPORT FOR NSW", "OPAL "], "Transport for NSW (Opal)", .publicTransport, 0.97),
            (["MYKI", "PTV "], "PTV Myki", .publicTransport, 0.97),
            (["TRANSLINK"], "Translink QLD", .publicTransport, 0.96),
            (["LINKT", "E-TOLL", "ROAM EXPRESS"], "Linkt Tolls", .fuelTollsVehicle, 0.94),
            (["AMPOL", "CALTEX", "BP ", "SHELL COLES EXPRESS", "7-ELEVEN FUEL"], "Service Station / Fuel", .fuelTollsVehicle, 0.90),
            (["UBER *TRIP", "DIDI "], "Rideshare (Uber / DiDi)", .fuelTollsVehicle, 0.89),
            (["UBER *EATS", "MENULOG", "DOORDASH"], "Food Delivery", .restaurantsAndDelivery, 0.93),
            (["SINGLE O", "CAMPOS", "PROUD MARY", "CAFE", "COFFEE", "ESPRESSO", "BAKERY"], "Local Cafe & Coffee", .cafesAndTakeaway, 0.88),
            (["ORIGIN ENERGY", "AGL ", "ENERGYAUSTRALIA", "RED ENERGY", "SYDNEY WATER", "YARRA VALLEY WATER", "AUSSIE BROADBAND", "NBN "], "Utilities & Internet", .utilitiesAndInternet, 0.95),
            (["TELSTRA", "OPTUS", "VODAFONE", "BOOST MOBILE", "BELONG"], "Mobile Provider", .mobilePhone, 0.95),
            (["MEDIBANK", "BUPA", "HCF ", "NIB ", "NRMA INSURANCE", "AAMI", "ALLIANZ"], "Insurance Provider", .insurance, 0.94),
            (["CHEMIST WAREHOUSE", "PRICELINE PHARMACY", "TERRYWHITE", "MEDICAL CENTRE", "DENTAL"], "Pharmacy & Healthcare", .healthcareMedicare, 0.92),
            (["ATO HECS", "HELP REPAYMENT"], "ATO HECS-HELP", .hecsHelp, 0.95),
            (["COUNCIL RATES", "STRATA"], "Council Rates & Strata", .councilRatesStrata, 0.93),
            (["ANYTIME FITNESS", "FITNESS FIRST", "F45 ", "JETTS", "VIRGIN ACTIVE"], "Gym & Fitness", .gymFitness, 0.94),
            (["NETFLIX", "SPOTIFY", "APPLE.COM/BILL", "STAN.COM.AU", "KAYO SPORTS", "BINGE"], "Streaming Subscription", .streamingSubscriptions, 0.95),
            (["AFTERPAY", "ZIP PAY", "ZIP MONEY", "PAYPAL PAY IN 4"], "Buy Now, Pay Later", .buyNowPayLater, 0.95),
            (["BUNNINGS", "KMART", "TARGET AU", "JB HI-FI", "OFFICEWORKS", "MYER", "DAVID JONES", "THE ICONIC", "MECCA"], "Retail Shopping", .shoppingRetail, 0.91),
            (["QANTAS", "VIRGIN AUSTRALIA", "JETSTAR", "AIRBNB", "BOOKING.COM"], "Domestic Travel & Stays", .domesticTravelHolidays, 0.92),
            (["RENT ", "REAL ESTATE", "PROPERTY MGMT", "MORTGAGE REPAYMENT"], "Rent / Mortgage", .rentAndMortgage, 0.94),
            (["AUSTRALIANSuper", "HOSTPLUS", "ART SUPER", "UNISUPER", "AWARE SUPER"], "Superannuation", .superannuation, 0.94),
            (["ATM WITHDRAWAL", "CASH OUT"], "ATM / Cash Withdrawal", .cashAndUnclassified, 0.90)
        ]

        for entry in rules {
            for kw in entry.keywords where upper.contains(kw) {
                let kind: TransactionKind = (entry.category == .cashAndUnclassified) ? .cashWithdrawal : defaultPurchaseKind
                return ClassificationResult(
                    normalizedMerchant: entry.merchant == "Retail Shopping" || entry.merchant == "Local Cafe & Coffee" ? cleanMerchantDisplayName(trimmed) : entry.merchant,
                    category: entry.category,
                    kind: kind,
                    paymentRail: detectedRail,
                    confidence: entry.confidence
                )
            }
        }

        // 6. Ambiguous / unknown merchant — do NOT guess blindly; flag low confidence (< 0.70)
        return ClassificationResult(
            normalizedMerchant: cleanMerchantDisplayName(trimmed.isEmpty ? "Unclassified Transaction" : trimmed),
            category: .cashAndUnclassified,
            kind: direction == .credit ? .income : defaultPurchaseKind,
            paymentRail: detectedRail,
            confidence: 0.40
        )
    }

    private static func cleanMerchantDisplayName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "VISA DEBIT PURCHASE ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "EFTPOS DEBIT ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "DIRECT DEBIT ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? raw : stripped
    }

    // MARK: - 6. Recurring Bills & Subscriptions Predictor

    public static func detectRecurringPayments(
        tenantId: String,
        transactions: [TransactionRecord],
        existingPredictions: [RecurringPaymentPrediction]
    ) -> [RecurringPaymentPrediction] {
        let expenseTxs = transactions.filter {
            $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment && isIncludedTransaction($0)
        }

        let grouped = Dictionary(grouping: expenseTxs) { $0.merchantName.lowercased() }
        var detected: [RecurringPaymentPrediction] = []

        for (_, group) in grouped {
            let sorted = group.sorted { $0.occurredAt < $1.occurredAt }
            guard let latest = sorted.last else { continue }

            // Check if already tracked in existingPredictions
            if let existing = existingPredictions.first(where: { $0.merchantName.caseInsensitiveCompare(latest.merchantName) == .orderedSame }) {
                var updated = existing
                updated.lastPaymentDate = latest.occurredAt
                updated.expectedAmountCents = latest.amountCents
                let linkedIds = Array(Set(existing.linkedTransactionIds + sorted.map(\.id)))
                updated.linkedTransactionIds = linkedIds
                detected.append(updated)
                continue
            }

            // Require at least 2 occurrences or an explicit isRecurring flag
            guard sorted.count >= 2 || latest.isRecurring else { continue }

            var inferredFrequency: RecurringFrequency = .monthly
            var confidence: PredictionConfidence = .medium

            if sorted.count >= 2 {
                let prev = sorted[sorted.count - 2]
                let dayDiff = max(1, Int(round(latest.occurredAt.timeIntervalSince(prev.occurredAt) / 86400.0)))
                if (5...9).contains(dayDiff) {
                    inferredFrequency = .weekly
                    confidence = .high
                } else if (12...16).contains(dayDiff) {
                    inferredFrequency = .fortnightly
                    confidence = .high
                } else if (26...35).contains(dayDiff) {
                    inferredFrequency = .monthly
                    confidence = .high
                } else if (80...100).contains(dayDiff) {
                    inferredFrequency = .quarterly
                    confidence = .medium
                } else {
                    confidence = .low
                }
            }

            let auCal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
            let nextDate = auCal.date(
                byAdding: .day,
                value: inferredFrequency.approximateDays,
                to: latest.occurredAt
            ) ?? latest.occurredAt.addingTimeInterval(Double(inferredFrequency.approximateDays) * 86400)

            detected.append(
                RecurringPaymentPrediction(
                    id: UUID(),
                    tenantId: tenantId,
                    merchantName: latest.merchantName,
                    category: latest.category,
                    expectedAmountCents: latest.amountCents,
                    frequency: inferredFrequency,
                    nextExpectedDate: nextDate,
                    lastPaymentDate: latest.occurredAt,
                    confidence: confidence,
                    isConfirmedByUser: false,
                    isDismissed: false,
                    paymentRail: latest.paymentRail ?? "Card / Direct Debit",
                    linkedTransactionIds: sorted.map(\.id)
                )
            )
        }

        let detectedMerchants = Set(detected.map { $0.merchantName.lowercased() })
        detected.append(contentsOf: existingPredictions.filter {
            !detectedMerchants.contains($0.merchantName.lowercased())
        })

        return detected
            .sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }

    // MARK: - 7. Deterministic Insights Engine

    public static func generateDeterministicInsights(
        referenceDate: Date,
        profile: UserProfile,
        summary: DailyAllowanceSummary,
        transactions: [TransactionRecord],
        recurringBills: [RecurringPaymentPrediction],
        categoryProgress: [CategoryBudgetProgress],
        savingsGoals: [SavingsGoal]
    ) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)

        // Insight 1: Upcoming bills due before next payday
        let billsBeforePayday = recurringBills.filter { bill in
            !bill.isDismissed && bill.nextExpectedDate >= cal.startOfDay(for: referenceDate) && bill.nextExpectedDate <= profile.nextPayDate
        }
        if !billsBeforePayday.isEmpty {
            let totalDueCents = billsBeforePayday.reduce(MoneyCents(0)) { $0 + $1.expectedAmountCents }
            let names = billsBeforePayday.prefix(3).map(\.merchantName).joined(separator: ", ")
            let linkedIds = billsBeforePayday.flatMap(\.linkedTransactionIds)
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "You have \(billsBeforePayday.count) recurring payment\(billsBeforePayday.count == 1 ? "" : "s") due before payday",
                    summary: "Upcoming commitments (\(names)) total \(AustralianMoneyFormatter.format(cents: totalDueCents)) before \(AustralianDateHelper.formatShortDate(profile.nextPayDate, timeZoneId: profile.timeZoneId)).",
                    calculationDetail: "Sum of \(billsBeforePayday.count) confirmed/predicted bills falling between today and your configured next pay date.",
                    actionableRecommendation: "Your daily allowance already reserves confirmed fixed commitments, so your Everyday Account only needs \(AustralianMoneyFormatter.format(cents: totalDueCents)) ready for direct debits.",
                    severity: .headsUp,
                    relatedCategory: billsBeforePayday.first?.category,
                    supportingTransactionIds: linkedIds,
                    isDeterministic: true
                )
            )
        }

        // Insight 2: Category pacing / grocery or cafe trajectory
        if let topCategory = categoryProgress.first {
            let catBounds = categoryBudgetPeriodBounds(
                for: topCategory.sourcePeriodType,
                referenceDate: referenceDate,
                profile: profile
            )
            let periodNoun = topCategory.sourcePeriodType.shortPeriodLabel
            let pct = Int(round(topCategory.percentageUsed * 100))
            if topCategory.isOverBudget {
                let overBy = topCategory.netSpentCents - topCategory.budgetedCents
                insights.append(
                    FinancialInsight(
                        id: UUID(),
                        title: "\(topCategory.category.displayName) is \(AustralianMoneyFormatter.format(cents: overBy)) above your \(periodNoun) target",
                        summary: "You've spent \(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) against a \(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents))/\(periodNoun) target.",
                        calculationDetail: "Net category spending (\(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) after any refunds) minus \(topCategory.sourcePeriodType.displayName.lowercased()) category budget (\(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents))).",
                        actionableRecommendation: "You can adjust your category limit or let your remaining daily allowance absorb the difference across the next \(catBounds.remainingDays) days.",
                        severity: .headsUp,
                        relatedCategory: topCategory.category,
                        supportingTransactionIds: topCategory.recentTransactions.map(\.id),
                        isDeterministic: true
                    )
                )
            } else if topCategory.projectedEndOfPeriodCents > topCategory.budgetedCents && pct >= 65 {
                insights.append(
                    FinancialInsight(
                        id: UUID(),
                        title: "At your current pace, you may exceed your \(topCategory.category.displayName) budget",
                        summary: "You've used \(pct)% (\(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents))) of your \(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents))/\(periodNoun) budget with \(catBounds.remainingDays) days left.",
                        calculationDetail: "Current \(periodNoun) spend \(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) projected across \(catBounds.totalDays) days equals \(AustralianMoneyFormatter.format(cents: topCategory.projectedEndOfPeriodCents)).",
                        actionableRecommendation: "Aim to keep \(topCategory.category.displayName) under \(AustralianMoneyFormatter.format(cents: max(0, topCategory.remainingCents / Int64(max(1, catBounds.remainingDays)))))/day for the rest of the \(periodNoun).",
                        severity: .neutral,
                        relatedCategory: topCategory.category,
                        supportingTransactionIds: topCategory.recentTransactions.map(\.id),
                        isDeterministic: true
                    )
                )
            }
        }

        // Insight 3: Cafes & Takeaway comparison
        let periodEndExclusive = cal.date(byAdding: .day, value: 1, to: summary.periodEnd) ?? summary.periodEnd
        let cafeTxs = transactions.filter {
            ($0.category == .cafesAndTakeaway || $0.category == .restaurantsAndDelivery) &&
            isIncludedTransaction($0) && !$0.excludeFromBudget &&
            $0.occurredAt >= summary.periodStart && $0.occurredAt < periodEndExclusive
        }
        let totalDiningCents = max(0, cafeTxs.reduce(MoneyCents(0)) {
            $0 + netSpendContributionCents(for: $1, categoryFilter: nil, includeFixedCategories: false)
        })
        let diningVisitCount = cafeTxs.filter {
            $0.direction == .debit
                && ($0.kind == .expense || $0.kind == .creditCardPurchase)
        }.count
        if diningVisitCount > 0 && totalDiningCents > 0 {
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "Cafes, coffee & dining check-in",
                    summary: "You've spent \(AustralianMoneyFormatter.format(cents: totalDiningCents)) across \(diningVisitCount) visit\(diningVisitCount == 1 ? "" : "s") during this budget period.",
                    calculationDetail: "Average visit is \(AustralianMoneyFormatter.format(cents: totalDiningCents / Int64(max(1, diningVisitCount)))) across \(diningVisitCount) eligible transaction\(diningVisitCount == 1 ? "" : "s").",
                    actionableRecommendation: "Tap to inspect the \(diningVisitCount) underlying cafe and takeaway transaction\(diningVisitCount == 1 ? "" : "s").",
                    severity: .neutral,
                    relatedCategory: .cafesAndTakeaway,
                    supportingTransactionIds: cafeTxs.map(\.id),
                    isDeterministic: true
                )
            )
        }

        // Insight 4: Savings goal trajectory
        if let primaryGoal = savingsGoals.first {
            let remainingGoalCents = max(0, primaryGoal.targetAmountCents - primaryGoal.currentSavedCents)
            let progressPct = primaryGoal.targetAmountCents > 0
                ? Int(round(Double(primaryGoal.currentSavedCents) / Double(primaryGoal.targetAmountCents) * 100))
                : 100
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "\(primaryGoal.name) is at \(progressPct)% of your target",
                    summary: "\(AustralianMoneyFormatter.format(cents: primaryGoal.currentSavedCents)) saved toward \(AustralianMoneyFormatter.format(cents: primaryGoal.targetAmountCents)) (\(AustralianMoneyFormatter.format(cents: remainingGoalCents)) remaining).",
                    calculationDetail: "Planned savings rate of \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents)) per \(summary.totalDaysInPeriod)-day period.",
                    actionableRecommendation: summary.plannedSavingsForPeriodCents > 0
                        ? "At your planned rate of \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents))/period, you are steadily building toward your goal."
                        : "Set a per-payday savings target in Budgets to automatically reserve contributions before calculating your daily allowance.",
                    severity: .positive,
                    relatedCategory: nil,
                    supportingTransactionIds: [],
                    isDeterministic: true
                )
            )
        }

        return insights
    }

    // MARK: - 8. Statement CSV Parsing, Reconciliation Fingerprint & Formula Sanitization

    /// Generates a deterministic reconciliation fingerprint.
    /// Includes `occurrenceIndexInBatch` so two legitimate identical purchases (e.g., two $4.80 Opal taps or coffees on the same day in the same statement)
    /// are NOT falsely discarded, while re-importing the same CSV file idempotently detects both as duplicates.
    public static func makeReconciliationFingerprint(
        accountId: UUID,
        date: Date,
        amountCents: MoneyCents,
        direction: TransactionDirection,
        rawDescription: String,
        sourceTransactionId: String?,
        occurrenceIndexInBatch: Int = 0
    ) -> String {
        if let srcId = sourceTransactionId, !srcId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sha256Hex("source|\(accountId.uuidString)|\(srcId.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let dayKey = formatter.string(from: date)
        let normDesc = rawDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "  ", with: " ")
        return sha256Hex("transaction|\(accountId.uuidString)|\(dayKey)|\(direction.rawValue)|\(amountCents)|\(normDesc)|\(occurrenceIndexInBatch)")
    }

    public static func makeStatementImportIdempotencyKey(
        accountId: UUID,
        fileName: String,
        csvContent: String
    ) -> String {
        let normalizedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "statement-\(sha256Hex("statement|\(accountId.uuidString)|\(normalizedFileName)|\(csvContent)"))"
    }

    public static func makeCSVRowFingerprint(accountId: UUID, rawLine: String) -> String {
        "invalid-\(sha256Hex("invalid-row|\(accountId.uuidString)|\(rawLine)"))"
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Prevents CSV Formula Injection (DDE / spreadsheet command execution) when exporting user data.
    /// Any field starting with `=`, `+`, `-`, `@`, `\t`, or `\r` is prefixed with a single quote `'` and properly quoted.
    public static func sanitizeCSVCell(_ value: String) -> String {
        var safe = value
        if let first = safe.first, ["=", "+", "-", "@", "\t", "\r"].contains(first) {
            safe = "'" + safe
        }
        let escaped = safe.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.hasPrefix("'") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    /// Auto-detects column mapping from the first row of an Australian bank CSV file.
    public static func detectCSVColumnMapping(csvText: String) -> (headers: [String], mapping: CSVColumnMapping) {
        guard let firstLine = parseCSVRows(csvText).first else {
            return (["Date", "Description", "Amount"], CSVColumnMapping(dateColumnIndex: 0, descriptionColumnIndex: 1, amountColumnIndex: 2, debitColumnIndex: nil, creditColumnIndex: nil, hasHeaderRow: true))
        }

        let columns = firstLine
        let lowerCols = columns.map { $0.lowercased() }

        let hasHeader = lowerCols.contains {
            $0.contains("date") || $0.contains("description") || $0.contains("narrative") || $0.contains("amount") || $0.contains("debit")
        }

        var dateIdx = 0
        var descIdx = min(1, max(0, columns.count - 1))
        var amountIdx: Int? = columns.count > 2 ? 2 : nil
        var debitIdx: Int? = nil
        var creditIdx: Int? = nil

        if hasHeader {
            for (idx, col) in lowerCols.enumerated() {
                if col.contains("date") {
                    dateIdx = idx
                } else if col.contains("description") || col.contains("narrative") || col.contains("merchant") || col.contains("details") || col.contains("payee") {
                    descIdx = idx
                } else if col.contains("debit") || col.contains("outflow") {
                    debitIdx = idx
                } else if col.contains("credit") || col.contains("inflow") {
                    creditIdx = idx
                } else if col.contains("amount") || col.contains("value") {
                    amountIdx = idx
                }
            }
            if debitIdx != nil && creditIdx != nil {
                amountIdx = nil
            }
        }

        let headers = hasHeader ? columns : columns.enumerated().map { "Column \($0.offset + 1)" }
        return (
            headers,
            CSVColumnMapping(
                dateColumnIndex: dateIdx,
                descriptionColumnIndex: descIdx,
                amountColumnIndex: amountIdx,
                debitColumnIndex: debitIdx,
                creditColumnIndex: creditIdx,
                hasHeaderRow: hasHeader
            )
        )
    }

    /// Parses CSV text into preview rows with validation, Australian date parsing, and duplicate detection.
    public static func previewCSVStatementImport(
        csvText: String,
        mapping: CSVColumnMapping,
        accountId: UUID,
        isCreditCardAccount: Bool,
        existingTransactions: [TransactionRecord],
        userMerchantRules: [MerchantRule],
        timeZoneId: String = AustralianTimeZone.sydney.rawValue
    ) -> [ParsedCSVRowPreview] {
        let rows = parseCSVRows(csvText)
        let nonEmptyRows = rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        let existingFingerprints = Set(existingTransactions.map(\.reconciliationFingerprint))
        var withinFileCollisionCounter: [String: Int] = [:]
        var previews: [ParsedCSVRowPreview] = []

        let startIndex = mapping.hasHeaderRow ? 1 : 0
        guard startIndex < nonEmptyRows.count else { return [] }

        for i in startIndex..<nonEmptyRows.count {
            let cols = nonEmptyRows[i]
            let rowNumber = i + 1

            let rawDateStr = cols.indices.contains(mapping.dateColumnIndex) ? cols[mapping.dateColumnIndex] : ""
            let rawDescStr = cols.indices.contains(mapping.descriptionColumnIndex) ? cols[mapping.descriptionColumnIndex] : ""

            let parsedDate = parseAustralianBankDate(rawDateStr, timeZoneId: timeZoneId)

            var parsedCents: MoneyCents? = nil
            var direction: TransactionDirection = .debit

            if let debitCol = mapping.debitColumnIndex, let creditCol = mapping.creditColumnIndex {
                let debitStr = cols.indices.contains(debitCol) ? cols[debitCol] : ""
                let creditStr = cols.indices.contains(creditCol) ? cols[creditCol] : ""
                if let dCents = AustralianMoneyFormatter.parseToCents(debitStr), dCents != 0 {
                    parsedCents = abs(dCents)
                    direction = .debit
                } else if let cCents = AustralianMoneyFormatter.parseToCents(creditStr), cCents != 0 {
                    parsedCents = abs(cCents)
                    direction = .credit
                }
            } else if let amtCol = mapping.amountColumnIndex, cols.indices.contains(amtCol) {
                if let signedCents = AustralianMoneyFormatter.parseToCents(cols[amtCol]), signedCents != 0 {
                    parsedCents = abs(signedCents)
                    direction = signedCents < 0 ? .debit : .credit
                }
            }

            var validationError: String? = nil
            if parsedDate == nil {
                validationError = "Invalid date '\(rawDateStr)' (expected DD/MM/YYYY or YYYY-MM-DD)"
            } else if parsedCents == nil {
                validationError = "Invalid or zero monetary amount"
            } else if rawDescStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "Missing transaction description"
            }

            let classification = classifyAustralianTransaction(
                rawDescription: rawDescStr,
                direction: direction,
                isCreditCardAccount: isCreditCardAccount,
                userMerchantRules: userMerchantRules
            )

            let baseKey = "\(rawDateStr)|\(rawDescStr)|\(parsedCents.map { String($0) } ?? "")|\(direction.rawValue)"
            let occurrenceIndex = withinFileCollisionCounter[baseKey, default: 0]
            withinFileCollisionCounter[baseKey] = occurrenceIndex + 1

            let fingerprint: String
            if let parsedDate, let parsedCents {
                fingerprint = makeReconciliationFingerprint(
                    accountId: accountId,
                    date: parsedDate,
                    amountCents: parsedCents,
                    direction: direction,
                    rawDescription: rawDescStr,
                    sourceTransactionId: nil,
                    occurrenceIndexInBatch: occurrenceIndex
                )
            } else {
                fingerprint = makeCSVRowFingerprint(accountId: accountId, rawLine: cols.joined(separator: ","))
            }

            let isDuplicate = existingFingerprints.contains(fingerprint)

            previews.append(
                ParsedCSVRowPreview(
                    id: UUID(),
                    rowNumber: rowNumber,
                    rawLine: cols.joined(separator: ","),
                    parsedDate: parsedDate,
                    parsedDescription: rawDescStr,
                    parsedAmountCents: parsedCents,
                    parsedDirection: direction,
                    inferredCategory: classification.category,
                    inferredKind: classification.kind,
                    classificationConfidence: classification.confidence,
                    fingerprint: fingerprint,
                    isDuplicate: isDuplicate,
                    validationError: validationError
                )
            )
        }

        return previews
    }

    public static func parseAustralianBankDate(_ raw: String, timeZoneId: String) -> Date? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
        guard !cleaned.isEmpty else { return nil }

        let formats = [
            "dd/MM/yyyy",
            "d/M/yyyy",
            "dd-MM-yyyy",
            "yyyy-MM-dd",
            "d MMM yyyy",
            "dd MMM yyyy",
            "d MMMM yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney")
        formatter.isLenient = false

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                // Set to 12:00 PM local time to avoid midnight boundary drift across time zones
                return date.addingTimeInterval(12 * 3600)
            }
        }
        return nil
    }

    /// Parses RFC 4180-style CSV records, including escaped quotes and embedded newlines.
    /// A final unterminated quoted field is retained as a row so the import workflow can
    /// surface it for repair instead of silently dropping data.
    public static func parseCSVRows(_ csvText: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = Data()
        var inQuotes = false
        let bytes = Array(csvText.utf8)
        var index = 0

        func decodedField(_ data: Data) -> String {
            String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? String(decoding: data, as: UTF8.self)
        }

        while index < bytes.count {
            let byte = bytes[index]
            if inQuotes {
                if byte == 34 {
                    let next = index + 1
                    if next < bytes.count, bytes[next] == 34 {
                        field.append(34)
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else {
                switch byte {
                case 34 where field.isEmpty:
                    inQuotes = true
                case 44:
                    row.append(decodedField(field))
                    field.removeAll(keepingCapacity: true)
                case 10, 13:
                    row.append(decodedField(field))
                    field.removeAll(keepingCapacity: true)
                    if !row.isEmpty { rows.append(row) }
                    row = []
                    if byte == 13 {
                        let next = index + 1
                        if next < bytes.count, bytes[next] == 10 {
                            index = next
                        }
                    }
                default:
                    field.append(byte)
                }
            }
            index += 1
        }

        if inQuotes || !field.isEmpty || !row.isEmpty {
            row.append(decodedField(field))
            rows.append(row)
        }
        return rows
    }

    public static func splitCSVRow(_ line: String) -> [String] {
        parseCSVRows(line).first ?? []
    }
}
