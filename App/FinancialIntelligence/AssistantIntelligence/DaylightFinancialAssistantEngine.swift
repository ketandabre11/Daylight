import Foundation

/// An on-device deterministic financial intelligence engine that analyzes the user's
/// actual transactions, Safe-to-Spend calculations, budgets, and savings records.
/// Strictly keeps all processing 100% on-device with zero external transmission.
public final class DaylightFinancialAssistantEngine: Sendable {
    public static let shared = DaylightFinancialAssistantEngine()

    public init() {}

    public func generateResponse(
        for prompt: String,
        store: DaylightStore
    ) -> (text: String, payload: AssistantPayload?) {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. "Where did my money go this month?" or category breakdown
        if cleaned.contains("where did my money go") || cleaned.contains("category breakdown") || cleaned.contains("categories") {
            return generateCategoryBreakdown(store: store)
        }

        // 2. "Why did my spending increase?" / Spending trend
        if cleaned.contains("spending increase") || cleaned.contains("why did my spending") || cleaned.contains("spending summary") {
            return generateSpendingSummary(store: store)
        }

        // 3. "How much did I save this month?" / Savings progress
        if cleaned.contains("how much did i save") || cleaned.contains("savings") || cleaned.contains("saved") {
            return generateSavingsProgress(store: store)
        }

        // 4. "What are my biggest expenses?" / Largest debit transactions
        if cleaned.contains("biggest expenses") || cleaned.contains("largest expenses") || cleaned.contains("biggest spend") {
            return generateBiggestExpenses(store: store)
        }

        // 5. "How much do I spend on subscriptions?" / Bills & recurring payments
        if cleaned.contains("subscriptions") || cleaned.contains("recurring") || cleaned.contains("bills") {
            return generateSubscriptionsSummary(store: store)
        }

        // 6. "Safe to spend" / daily allowance inquiry
        if cleaned.contains("safe to spend") || cleaned.contains("allowance") || cleaned.contains("daily limit") {
            let summary = store.allowanceSummary
            let formattedRemaining = AustralianMoneyFormatter.format(cents: summary.todaysRemainingAllowanceCents)
            let formattedBaseline = AustralianMoneyFormatter.format(cents: summary.baselineDailyAllowanceCents)
            let daysLeft = summary.remainingDaysInPeriod
            let text = "Your Safe-to-Spend for today is \(formattedRemaining). Your baseline allowance is \(formattedBaseline) per day, calculated across the remaining \(daysLeft) days of your current pay cycle until your next payday."
            return (text, nil)
        }

        // Default intelligent fallback based on user's current Safe-to-Spend and top activity
        let summary = store.allowanceSummary
        let remaining = AustralianMoneyFormatter.format(cents: summary.todaysRemainingAllowanceCents)
        let spentToday = AustralianMoneyFormatter.format(cents: summary.flexibleSpentTodayCents)
        let text = "Based on your verified accounts, you have \(remaining) safe to spend today with \(spentToday) spent so far. Feel free to ask about your categories, biggest expenses, subscriptions, or savings goals."
        return (text, nil)
    }

    // MARK: - Category Breakdown Analysis

    private func generateCategoryBreakdown(store: DaylightStore) -> (text: String, payload: AssistantPayload?) {
        let debits = store.transactions.filter { $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment }
        guard !debits.isEmpty else {
            return ("No expense transactions were recorded for this period yet.", nil)
        }

        var totalsByCategory: [AustralianCategory: MoneyCents] = [:]
        var overallTotal: MoneyCents = 0

        for tx in debits {
            totalsByCategory[tx.category, default: 0] += tx.amountCents
            overallTotal += tx.amountCents
        }

        let sorted = totalsByCategory.sorted { $0.value > $1.value }
        let slices: [AssistantCategorySlice] = sorted.prefix(5).map { item in
            let percentage = overallTotal > 0 ? (Double(item.value) / Double(overallTotal)) : 0.0
            return AssistantCategorySlice(
                categoryName: item.key.displayName,
                icon: item.key.symbolName,
                amountCents: item.value,
                percentage: percentage
            )
        }

        let top = slices.first
        let topName = top?.categoryName ?? "General"
        let topAmount = AustralianMoneyFormatter.format(cents: top?.amountCents ?? 0)
        let totalStr = AustralianMoneyFormatter.format(cents: overallTotal)

        let text = "You have spent a total of \(totalStr) across \(debits.count) expense transactions. Your largest category was \(topName) at \(topAmount) (\(Int((top?.percentage ?? 0) * 100))% of total spending)."

        return (text, .categoryBreakdown(slices))
    }

    // MARK: - Spending Summary Analysis

    private func generateSpendingSummary(store: DaylightStore) -> (text: String, payload: AssistantPayload?) {
        let summary = store.allowanceSummary
        let totalFlexibleSpent = summary.totalFlexibleSpentInPeriodCents
        let totalFlexibleBudget = summary.totalFlexibleBudgetForPeriodCents
        let daysPassed = max(1, 14 - summary.remainingDaysInPeriod)
        let dailyAverage = totalFlexibleSpent / Int64(daysPassed)

        let debits = store.transactions.filter { $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment }
        var catTotals: [AustralianCategory: MoneyCents] = [:]
        for tx in debits {
            catTotals[tx.category, default: 0] += tx.amountCents
        }
        let topCat = catTotals.max { $0.value < $1.value }
        let topCatName = topCat?.key.displayName ?? "Flexible Spending"
        let topCatCents = topCat?.value ?? 0

        let formattedSpent = AustralianMoneyFormatter.format(cents: totalFlexibleSpent)
        let formattedBudget = AustralianMoneyFormatter.format(cents: totalFlexibleBudget)
        let formattedAvg = AustralianMoneyFormatter.format(cents: dailyAverage)

        let comparisonText: String
        if totalFlexibleSpent > totalFlexibleBudget {
            comparisonText = "You have exceeded your total flexible budget of \(formattedBudget) for this period. The largest contributing area was \(topCatName)."
        } else {
            let remaining = AustralianMoneyFormatter.format(cents: summary.remainingFlexibleBudgetForPeriodCents)
            comparisonText = "You are tracking well within your flexible budget with \(remaining) remaining until your next payday. Your average daily burn is \(formattedAvg)."
        }

        let payloadData = SpendingSummaryData(
            title: "Period Spending Summary",
            periodLabel: "Current Pay Period",
            totalSpentCents: totalFlexibleSpent,
            dailyAverageCents: dailyAverage,
            topCategoryName: topCatName,
            topCategoryCents: topCatCents
        )

        return (comparisonText, .spendingSummary(payloadData))
    }

    // MARK: - Savings Progress Analysis

    private func generateSavingsProgress(store: DaylightStore) -> (text: String, payload: AssistantPayload?) {
        let goals = store.savingsGoals
        let totalSaved = goals.reduce(into: MoneyCents(0)) { $0 += $1.currentSavedCents }
        let totalTarget = goals.reduce(into: MoneyCents(0)) { $0 += $1.targetAmountCents }
        let formattedSaved = AustralianMoneyFormatter.format(cents: totalSaved)

        if goals.isEmpty {
            return ("You haven't set any savings goals yet. You can create a goal anytime from the Savings tab.", nil)
        }

        let sortedGoals = goals.sorted(by: { $0.currentSavedCents > $1.currentSavedCents })
        let topGoal = sortedGoals.first
        let topGoalProgress = topGoal != nil && topGoal!.targetAmountCents > 0
            ? Double(topGoal!.currentSavedCents) / Double(topGoal!.targetAmountCents)
            : 0.0

        let formattedTarget = AustralianMoneyFormatter.format(cents: totalTarget)
        let text = "Across your \(goals.count) active savings goals, you have accumulated \(formattedSaved) of your \(formattedTarget) aggregate target."

        let payloadData = SavingsProgressData(
            totalSavedCents: totalSaved,
            activeGoalsCount: goals.count,
            topGoalName: topGoal?.name ?? "General Savings",
            topGoalProgress: topGoalProgress
        )

        return (text, .savingsProgress(payloadData))
    }

    // MARK: - Biggest Expenses Analysis

    private func generateBiggestExpenses(store: DaylightStore) -> (text: String, payload: AssistantPayload?) {
        let debits = store.transactions
            .filter { $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment }
            .sorted(by: { $0.amountCents > $1.amountCents })

        guard !debits.isEmpty else {
            return ("No recorded expenses to evaluate.", nil)
        }

        let top3 = debits.prefix(3)
        var descriptions: [String] = []
        for (idx, tx) in top3.enumerated() {
            descriptions.append("#\(idx + 1) \(tx.merchantName) (\(AustralianMoneyFormatter.format(cents: tx.amountCents)))")
        }

        let text = "Your top recorded expenses were:\n" + descriptions.joined(separator: "\n")
        return (text, nil)
    }

    // MARK: - Subscriptions Summary Analysis

    private func generateSubscriptionsSummary(store: DaylightStore) -> (text: String, payload: AssistantPayload?) {
        let bills = store.recurringPredictions
        guard !bills.isEmpty else {
            return ("No recurring subscriptions or predicted bills are currently recorded.", nil)
        }

        let totalMonthly = bills.reduce(into: MoneyCents(0)) { $0 += $1.expectedAmountCents }
        let formattedTotal = AustralianMoneyFormatter.format(cents: totalMonthly)

        let items: [SubscriptionItemSnapshot] = bills.prefix(6).map { bill in
            SubscriptionItemSnapshot(
                merchantName: bill.merchantName,
                cadence: bill.frequency.displayName,
                amountCents: bill.expectedAmountCents
            )
        }

        let text = "You have \(bills.count) recurring commitments and subscriptions totalling approximately \(formattedTotal) each cycle."
        let payloadData = SubscriptionsData(
            totalMonthlyCents: totalMonthly,
            count: bills.count,
            items: items
        )

        return (text, .subscriptionsSummary(payloadData))
    }
}
