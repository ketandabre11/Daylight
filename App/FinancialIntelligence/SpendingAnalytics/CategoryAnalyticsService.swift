import Foundation

/// Analyzes category-level expenditure, budget utilisation, growth rates, and shifts over time.
public final class CategoryAnalyticsService: Sendable {
    public static let shared = CategoryAnalyticsService()

    public init() {}

    public func analyzeCategories(
        currentPeriodTransactions: [TransactionRecord],
        previousPeriodTransactions: [TransactionRecord],
        categoryBudgets: [CategoryBudget],
        historicalTransactions: [TransactionRecord] = [],
        timeZoneId: String = "Australia/Sydney",
        isEquivalentPeriodComparison: Bool = false
    ) -> [CategorySpendingAnalytics] {
        // 1. Calculate total expenses across all categories for proportion calculation
        var currentSpendByCat: [AustralianCategory: MoneyCents] = [:]
        var txCountByCat: [AustralianCategory: Int] = [:]
        var overallTotalExpensesCents: MoneyCents = 0

        for cat in AustralianCategory.expenseCategories {
            var catNet: MoneyCents = 0
            var count = 0
            for tx in currentPeriodTransactions {
                let contrib = FinancialCalculationEngine.netSpendContributionCents(
                    for: tx,
                    categoryFilter: cat,
                    includeFixedCategories: true
                )
                if contrib != 0 {
                    catNet += contrib
                    count += 1
                }
            }
            if catNet > 0 {
                currentSpendByCat[cat] = catNet
                txCountByCat[cat] = count
                overallTotalExpensesCents += catNet
            }
        }

        // 2. Previous period spending by category
        var previousSpendByCat: [AustralianCategory: MoneyCents] = [:]
        for cat in AustralianCategory.expenseCategories {
            var prevNet: MoneyCents = 0
            for tx in previousPeriodTransactions {
                let contrib = FinancialCalculationEngine.netSpendContributionCents(
                    for: tx,
                    categoryFilter: cat,
                    includeFixedCategories: true
                )
                if contrib != 0 {
                    prevNet += contrib
                }
            }
            if prevNet > 0 {
                previousSpendByCat[cat] = prevNet
            }
        }

        // 3. Historical monthly average (if historical transactions provided)
        var historicalAverageByCat: [AustralianCategory: MoneyCents] = [:]
        if !historicalTransactions.isEmpty {
            let cal = AustralianDateHelper.calendar(for: timeZoneId)
            // Group by year and month
            var monthlySums: [AustralianCategory: [String: MoneyCents]] = [:]
            for tx in historicalTransactions {
                let ym = cal.dateComponents([.year, .month], from: tx.occurredAt)
                let key = "\(ym.year ?? 0)-\(ym.month ?? 0)"
                for cat in AustralianCategory.expenseCategories {
                    let contrib = FinancialCalculationEngine.netSpendContributionCents(
                        for: tx,
                        categoryFilter: cat,
                        includeFixedCategories: true
                    )
                    if contrib != 0 {
                        monthlySums[cat, default: [:]][key, default: 0] += contrib
                    }
                }
            }
            for (cat, monthDict) in monthlySums {
                let validMonths = monthDict.values.filter { $0 > 0 }
                if !validMonths.isEmpty {
                    let avg = validMonths.reduce(MoneyCents(0), +) / Int64(validMonths.count)
                    historicalAverageByCat[cat] = avg
                }
            }
        }

        // 4. Map active category budgets normalized to monthly
        var budgetMap: [AustralianCategory: MoneyCents] = [:]
        for b in categoryBudgets {
            let monthlyLimit = FinancialCalculationEngine.normalizedAmountForCalculation(
                amountCents: b.limitCents,
                from: b.periodType,
                to: .monthly
            )
            budgetMap[b.category] = monthlyLimit
        }

        // 5. Build raw analytics list
        var results: [CategorySpendingAnalytics] = []

        // Include all expense categories that had spending in either period, or have an active budget
        var relevantCategories = Set(currentSpendByCat.keys)
        relevantCategories.formUnion(previousSpendByCat.keys)
        relevantCategories.formUnion(budgetMap.keys)

        for cat in relevantCategories {
            let currentSpend = currentSpendByCat[cat] ?? 0
            let prevSpend = previousSpendByCat[cat] ?? 0
            let count = txCountByCat[cat] ?? 0
            let budgeted = budgetMap[cat]

            let change = SpendingComparison(
                currentAmountCents: currentSpend,
                previousAmountCents: prevSpend,
                isEquivalentPeriodComparison: isEquivalentPeriodComparison,
                comparisonContextLabel: isEquivalentPeriodComparison ? "Equivalent days" : "Full month"
            )

            let share = overallTotalExpensesCents > 0
                ? (Double(currentSpend) / Double(overallTotalExpensesCents))
                : 0.0

            let utilisation: Double?
            let remaining: MoneyCents?
            if let budget = budgeted, budget > 0 {
                utilisation = Double(currentSpend) / Double(budget)
                remaining = budget - currentSpend
            } else {
                utilisation = nil
                remaining = nil
            }

            let histAvg = historicalAverageByCat[cat]

            let item = CategorySpendingAnalytics(
                category: cat,
                currentSpendingCents: currentSpend,
                previousSpendingCents: prevSpend,
                change: change,
                shareOfTotalExpenses: share,
                budgetedCents: budgeted,
                budgetUtilisation: utilisation,
                remainingBudgetCents: remaining,
                historicalMonthlyAverageCents: histAvg,
                transactionCount: count,
                isDecreasing: change.direction == .decreased,
                isApproachingBudget: (utilisation ?? 0) >= 0.80 && (utilisation ?? 0) <= 1.0,
                isExceedingBudget: (utilisation ?? 0) > 1.0
            )
            results.append(item)
        }

        // 6. Sort by current spending descending
        results.sort { $0.currentSpendingCents > $1.currentSpendingCents }

        // 7. Mark highest spending & fastest growing
        if let first = results.first, first.currentSpendingCents > 0 {
            results[0].isHighestSpending = true
        }

        // Find fastest growing with meaningful dollar increase (>= $25.00 = 2,500 cents)
        var fastestIndex: Int? = nil
        var maxGrowthPct: Double = 0.0
        for (idx, item) in results.enumerated() {
            if let pct = item.change.percentageChange, pct > maxGrowthPct, item.change.absoluteChangeCents >= 2_500 {
                maxGrowthPct = pct
                fastestIndex = idx
            }
        }
        if let fIdx = fastestIndex {
            results[fIdx].isFastestGrowing = true
        }

        return results
    }
}
