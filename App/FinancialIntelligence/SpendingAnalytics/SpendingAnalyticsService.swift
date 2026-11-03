import Foundation

/// Primary calculation service for monthly and period-based spending analytics.
/// Adheres strictly to MoneyCents = Int64 arithmetic, Australian date conventions,
/// like-for-like elapsed period comparisons, and internal transfer exclusions.
public final class SpendingAnalyticsService: Sendable {
    public static let shared = SpendingAnalyticsService()

    public init() {}

    public func calculateMonthlyAnalytics(
        forYear year: Int,
        month: Int,
        referenceDate: Date,
        transactions: [TransactionRecord],
        categoryBudgets: [CategoryBudget],
        savingsGoals: [SavingsGoal] = [],
        timeZoneId: String = "Australia/Sydney"
    ) -> MonthlySpendingAnalytics {
        let cal = AustralianDateHelper.calendar(for: timeZoneId)

        // 1. Determine period boundaries
        var startComps = DateComponents()
        startComps.year = year
        startComps.month = month
        startComps.day = 1
        let monthStart = cal.date(from: startComps) ?? referenceDate

        let monthEndExclusive = cal.date(byAdding: .month, value: 1, to: monthStart) ?? referenceDate
        let totalDays = cal.dateComponents([.day], from: monthStart, to: monthEndExclusive).day ?? 30

        let startOfRefDay = cal.startOfDay(for: referenceDate)
        let isCurrentMonth = referenceDate >= monthStart && referenceDate < monthEndExclusive
        let isFutureMonth = referenceDate < monthStart

        let elapsedDays: Int
        let isComplete: Bool

        if isCurrentMonth {
            let dayNum = cal.component(.day, from: referenceDate)
            elapsedDays = max(1, min(totalDays, dayNum))
            isComplete = false
        } else if isFutureMonth {
            elapsedDays = 0
            isComplete = false
        } else {
            elapsedDays = totalDays
            isComplete = true
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_AU")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "MMMM yyyy"
        let monthTitle = fmt.string(from: monthStart)

        let reportingPeriod = AnalyticsReportingPeriod(
            type: .calendarMonth(year: year, month: month),
            title: monthTitle,
            startDate: monthStart,
            endDateExclusive: monthEndExclusive,
            elapsedDays: elapsedDays,
            totalDays: totalDays,
            isComplete: isComplete
        )

        // 2. Filter transactions in the current target month
        let currentMonthTxs = transactions.filter { tx in
            tx.occurredAt >= monthStart && tx.occurredAt < monthEndExclusive
        }

        // 3. Determine previous month boundaries for comparison
        let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let prevMonthEndExclusive = monthStart

        // If current month is incomplete, calculate an equivalent elapsed cutoff for like-for-like comparison
        let prevComparisonEnd: Date
        let isEquivalentPeriod: Bool
        let contextLabel: String

        if isCurrentMonth && elapsedDays < totalDays {
            prevComparisonEnd = cal.date(byAdding: .day, value: elapsedDays, to: prevMonthStart) ?? prevMonthEndExclusive
            isEquivalentPeriod = true
            let daySuffix = elapsedDays == 1 ? "1st" : "first \(elapsedDays) days"
            contextLabel = "Compared with \(daySuffix) of last month"
        } else {
            prevComparisonEnd = prevMonthEndExclusive
            isEquivalentPeriod = false
            contextLabel = "Full month comparison"
        }

        let prevMonthComparisonTxs = transactions.filter { tx in
            tx.occurredAt >= prevMonthStart && tx.occurredAt < prevComparisonEnd
        }

        // 4. Calculate Income
        let totalIncome = currentMonthTxs
            .filter { FinancialCalculationEngine.isVerifiedIncome($0) }
            .reduce(MoneyCents(0)) { $0 + $1.amountCents }

        // 5. Calculate Expenses (net of refunds, excluding non-spend transfers)
        let totalExpenses = currentMonthTxs
            .reduce(MoneyCents(0)) { partial, tx in
                partial + FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
            }
        let safeTotalExpenses = max(0, totalExpenses)

        // Previous expenses
        let prevExpenses = prevMonthComparisonTxs
            .reduce(MoneyCents(0)) { partial, tx in
                partial + FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
            }
        let safePrevExpenses = max(0, prevExpenses)

        // 6. Calculate Refunds
        let totalRefunds = currentMonthTxs
            .filter {
                ($0.kind == .refund || $0.kind == .reversal)
                    && FinancialCalculationEngine.isVerifiedRefund($0)
            }
            .reduce(MoneyCents(0)) { $0 + $1.amountCents }

        // 7. Calculate Savings Contributions
        var totalSavings: MoneyCents = 0
        for goal in savingsGoals {
            for contrib in goal.contributions {
                if contrib.date >= monthStart && contrib.date < monthEndExclusive {
                    totalSavings += contrib.amountCents
                }
            }
        }

        // 8. Cash flow & Net flow
        let netCashFlow = totalIncome - safeTotalExpenses
        let savingsRate: Double?
        if totalIncome > 0 && totalSavings > 0 {
            savingsRate = min(100.0, (Double(totalSavings) / Double(totalIncome)) * 100.0)
        } else {
            savingsRate = nil
        }

        let cashFlow = CashFlowAnalytics(
            period: reportingPeriod,
            currency: "AUD",
            totalIncomeCents: totalIncome,
            totalExpensesCents: safeTotalExpenses,
            totalRefundsCents: totalRefunds,
            totalSavingsContributionsCents: totalSavings,
            netCashFlowCents: netCashFlow,
            savingsRate: savingsRate
        )

        // 9. Daily Average
        let divisor = max(1, elapsedDays)
        let dailyAverage = safeTotalExpenses / Int64(divisor)

        // 10. Month-over-Month Comparison
        let comparison: SpendingComparison?
        if safePrevExpenses > 0 || safeTotalExpenses > 0 {
            comparison = SpendingComparison(
                currentAmountCents: safeTotalExpenses,
                previousAmountCents: safePrevExpenses,
                isEquivalentPeriodComparison: isEquivalentPeriod,
                comparisonContextLabel: contextLabel
            )
        } else {
            comparison = nil
        }

        // 11. Weekly Breakdown (4 to 5 calendar weeks)
        let weeklyBreakdown = buildWeeklyBreakdown(
            monthStart: monthStart,
            monthEndExclusive: monthEndExclusive,
            transactions: currentMonthTxs,
            calendar: cal
        )

        // 12. Category Analytics
        let categoryAnalytics = CategoryAnalyticsService.shared.analyzeCategories(
            currentPeriodTransactions: currentMonthTxs,
            previousPeriodTransactions: prevMonthComparisonTxs,
            categoryBudgets: categoryBudgets,
            historicalTransactions: transactions,
            timeZoneId: timeZoneId,
            isEquivalentPeriodComparison: isEquivalentPeriod
        )

        // 13. Merchant Analytics
        let merchantAnalytics = MerchantAnalyticsService.shared.analyzeMerchants(
            currentPeriodTransactions: currentMonthTxs,
            previousPeriodTransactions: prevMonthComparisonTxs,
            totalExpensesCents: safeTotalExpenses
        )

        // 14. Spending Patterns
        let detectedPatterns = SpendingPatternDetectionService.shared.detectPatterns(
            currentTransactions: currentMonthTxs,
            previousTransactions: prevMonthComparisonTxs,
            categoryAnalytics: categoryAnalytics,
            merchantAnalytics: merchantAnalytics,
            totalExpensesCents: safeTotalExpenses,
            isEquivalentPeriodComparison: isEquivalentPeriod
        )

        // 15. Synthesize Actionable Insights
        let insights = buildSpendingInsights(
            reportingPeriod: reportingPeriod,
            totalExpenses: safeTotalExpenses,
            dailyAverage: dailyAverage,
            comparison: comparison,
            categories: categoryAnalytics,
            merchants: merchantAnalytics,
            patterns: detectedPatterns
        )

        return MonthlySpendingAnalytics(
            period: reportingPeriod,
            currency: "AUD",
            cashFlow: cashFlow,
            totalExpensesCents: safeTotalExpenses,
            dailyAverageCents: dailyAverage,
            comparisonToPreviousMonth: comparison,
            weeklyBreakdown: weeklyBreakdown,
            categories: categoryAnalytics,
            topMerchants: merchantAnalytics,
            detectedPatterns: detectedPatterns,
            insights: insights
        )
    }

    // MARK: - Weekly Breakdown Helper

    private func buildWeeklyBreakdown(
        monthStart: Date,
        monthEndExclusive: Date,
        transactions: [TransactionRecord],
        calendar cal: Calendar
    ) -> [WeeklySpendingAnalytics] {
        var weeks: [WeeklySpendingAnalytics] = []
        var curWeekStart = monthStart
        var weekIndex = 1

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_AU")
        monthFmt.timeZone = cal.timeZone
        monthFmt.dateFormat = "MMM"

        while curWeekStart < monthEndExclusive {
            let nextWeekRaw = cal.date(byAdding: .day, value: 7, to: curWeekStart) ?? monthEndExclusive
            let curWeekEnd = min(nextWeekRaw, monthEndExclusive)

            let weekTxs = transactions.filter { $0.occurredAt >= curWeekStart && $0.occurredAt < curWeekEnd }
            let spent = weekTxs.reduce(MoneyCents(0)) { partial, tx in
                partial + FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
            }
            let safeSpent = max(0, spent)
            let daysInWeek = max(1, cal.dateComponents([.day], from: curWeekStart, to: curWeekEnd).day ?? 7)
            let dailyAvg = safeSpent / Int64(daysInWeek)

            let startDay = cal.component(.day, from: curWeekStart)
            let incEnd = cal.date(byAdding: .day, value: -1, to: curWeekEnd) ?? curWeekStart
            let endDay = cal.component(.day, from: incEnd)
            let monthName = monthFmt.string(from: curWeekStart)
            let dateRange = "\(startDay)–\(endDay) \(monthName)"
            let fullLabel = "Week \(weekIndex)"
            let shortLabel = "Wk \(weekIndex)"

            weeks.append(
                WeeklySpendingAnalytics(
                    weekLabel: fullLabel,
                    shortLabel: shortLabel,
                    dateRangeLabel: dateRange,
                    weekIndex: weekIndex,
                    startDate: curWeekStart,
                    endDateExclusive: curWeekEnd,
                    spentCents: safeSpent,
                    dailyAverageCents: dailyAvg,
                    transactionCount: weekTxs.count
                )
            )

            curWeekStart = curWeekEnd
            weekIndex += 1
        }

        return weeks
    }

    // MARK: - Insights Synthesis Helper

    private func buildSpendingInsights(
        reportingPeriod: AnalyticsReportingPeriod,
        totalExpenses: MoneyCents,
        dailyAverage: MoneyCents,
        comparison: SpendingComparison?,
        categories: [CategorySpendingAnalytics],
        merchants: [MerchantSpendingAnalytics],
        patterns: [SpendingPattern]
    ) -> [SpendingInsight] {
        var list: [SpendingInsight] = []

        // Insight A: MoM spending trajectory
        if let comp = comparison, let pct = comp.percentageChange {
            let absStr = AustralianMoneyFormatter.format(cents: abs(comp.absoluteChangeCents))
            if comp.direction == .increased {
                list.append(
                    SpendingInsight(
                        title: "Spending increased by \(absStr)",
                        subtitle: "\(comp.comparisonContextLabel)",
                        detail: "Expenditure is tracking \(String(format: "%.1f", pct))% higher than \(comp.isEquivalentPeriodComparison ? "the same elapsed point last month" : "last month").",
                        recommendation: "Review recent grocery and dining expenses to ensure you remain on pace for your savings target.",
                        severity: .headsUp,
                        metricHeadline: "+\(String(format: "%.1f", pct))%"
                    )
                )
            } else if comp.direction == .decreased {
                list.append(
                    SpendingInsight(
                        title: "Spending decreased by \(absStr)",
                        subtitle: "\(comp.comparisonContextLabel)",
                        detail: "Outgoings are down \(String(format: "%.1f", abs(pct)))% compared to \(comp.isEquivalentPeriodComparison ? "the same elapsed point last month" : "last month").",
                        recommendation: "Consider allocating a portion of this month's surplus directly toward an active savings goal.",
                        severity: .positive,
                        metricHeadline: "-\(String(format: "%.1f", abs(pct)))%"
                    )
                )
            }
        }

        // Insight B: Top category concentration
        if let topCat = categories.first, topCat.currentSpendingCents > 0 {
            let catPct = Int(round(topCat.shareOfTotalExpenses * 100.0))
            let catAmount = AustralianMoneyFormatter.format(cents: topCat.currentSpendingCents)
            list.append(
                SpendingInsight(
                    title: "\(topCat.category.displayName) is your largest expense",
                    subtitle: "\(catAmount) (\(catPct)% of total spend)",
                    detail: "\(topCat.category.displayName) represents \(catPct)% of all recorded spending across \(topCat.transactionCount) transaction\(topCat.transactionCount == 1 ? "" : "s").",
                    recommendation: topCat.isApproachingBudget
                        ? "You have used \(Int(round((topCat.budgetUtilisation ?? 0) * 100)))% of your budget for this category."
                        : "Tracking your primary expense category helps preserve daily Safe-to-Spend.",
                    severity: topCat.isExceedingBudget ? .headsUp : .neutral,
                    relatedCategory: topCat.category,
                    metricHeadline: "\(catPct)%"
                )
            )
        }

        // Insight C: Turn high-severity patterns into featured insights
        for p in patterns.prefix(2) {
            list.append(
                SpendingInsight(
                    title: p.title,
                    subtitle: p.summary,
                    detail: p.supportingEvidence.joined(separator: " • "),
                    recommendation: "Evidence-backed observation derived from your verified transactions.",
                    severity: p.severity,
                    supportingTransactionIds: p.supportingTransactionIds
                )
            )
        }

        return list
    }
}
