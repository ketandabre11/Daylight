import Foundation

/// Detects meaningful financial patterns, behavioural shifts, and spending anomalies.
public final class SpendingPatternDetectionService: Sendable {
    public static let shared = SpendingPatternDetectionService()

    public init() {}

    public func detectPatterns(
        currentTransactions: [TransactionRecord],
        previousTransactions: [TransactionRecord],
        categoryAnalytics: [CategorySpendingAnalytics],
        merchantAnalytics: [MerchantSpendingAnalytics],
        totalExpensesCents: MoneyCents,
        isEquivalentPeriodComparison: Bool
    ) -> [SpendingPattern] {
        var patterns: [SpendingPattern] = []

        // Guard against insufficient data (need at least 3 transactions to detect any pattern)
        guard currentTransactions.count >= 3 else {
            return []
        }

        let hasPreviousHistory = !previousTransactions.isEmpty

        // 1. Increasing Groceries
        if hasPreviousHistory, let groceryItem = categoryAnalytics.first(where: { $0.category == .groceries }) {
            let change = groceryItem.change
            if change.direction == .increased,
               let pct = change.percentageChange, pct >= 15.0,
               change.absoluteChangeCents >= 4_000 { // >= $40 increase
                let groceryTxs = currentTransactions.filter { $0.category == .groceries }
                patterns.append(
                    SpendingPattern(
                        type: .increasingGroceries,
                        title: "Grocery Spending Trended Up",
                        summary: "Supermarket expenditure increased by \(AustralianMoneyFormatter.format(cents: change.absoluteChangeCents)) (+\(String(format: "%.1f", pct))%) compared with \(isEquivalentPeriodComparison ? "the equivalent period last month" : "last month").",
                        severity: .headsUp,
                        supportingEvidence: [
                            "Current spend: \(AustralianMoneyFormatter.format(cents: groceryItem.currentSpendingCents)) across \(groceryItem.transactionCount) transactions",
                            "Previous spend: \(AustralianMoneyFormatter.format(cents: groceryItem.previousSpendingCents))",
                            "Average per visit: \(AustralianMoneyFormatter.format(cents: groceryItem.transactionCount > 0 ? groceryItem.currentSpendingCents / Int64(groceryItem.transactionCount) : 0))"
                        ],
                        supportingTransactionIds: groceryTxs.map(\.id),
                        significanceScore: min(0.9, 0.5 + (pct / 100.0) * 0.2)
                    )
                )
            }
        }

        // 2. Increasing Dining & Takeaway
        if hasPreviousHistory, let diningItem = categoryAnalytics.first(where: { $0.category == .cafesAndTakeaway || $0.category == .restaurantsAndDelivery }) {
            let change = diningItem.change
            if change.direction == SpendingComparison.Direction.increased,
               let pct = change.percentageChange, pct >= 20.0,
               change.absoluteChangeCents >= 3_000 { // >= $30 increase
                let diningTxs = currentTransactions.filter { $0.category == diningItem.category }
                let diningTxIds = diningTxs.map { $0.id }
                patterns.append(
                    SpendingPattern(
                        type: .increasingDining,
                        title: "Higher Dining & Takeaway",
                        summary: "\(diningItem.category.displayName) increased by \(AustralianMoneyFormatter.format(cents: change.absoluteChangeCents)) (+\(String(format: "%.1f", pct))%).",
                        severity: .headsUp,
                        supportingEvidence: [
                            "Current spend: \(AustralianMoneyFormatter.format(cents: diningItem.currentSpendingCents))",
                            "Previous spend: \(AustralianMoneyFormatter.format(cents: diningItem.previousSpendingCents))",
                            "Transactions: \(diningItem.transactionCount)"
                        ],
                        supportingTransactionIds: diningTxIds,
                        significanceScore: min(0.85, 0.5 + (pct / 100.0) * 0.2)
                    )
                )
            }
        }

        // 3. Reduced Discretionary Spending (Positive Discipline)
        if hasPreviousHistory {
            let discretionaryCategories: Set<AustralianCategory> = [
                .cafesAndTakeaway, .restaurantsAndDelivery, .streamingSubscriptions,
                .shoppingRetail, .gymFitness
            ]
            let currentDisc = categoryAnalytics
                .filter { discretionaryCategories.contains($0.category) }
                .reduce(MoneyCents(0)) { $0 + $1.currentSpendingCents }
            let prevDisc = categoryAnalytics
                .filter { discretionaryCategories.contains($0.category) }
                .reduce(MoneyCents(0)) { $0 + $1.previousSpendingCents }

            if prevDisc > 10_000 && currentDisc < prevDisc {
                let saved = prevDisc - currentDisc
                let dropPct = (Double(saved) / Double(prevDisc)) * 100.0
                if dropPct >= 10.0 {
                    patterns.append(
                        SpendingPattern(
                            type: .reducedDiscretionary,
                            title: "Discretionary Spending Under Control",
                            summary: "Non-essential flexible expenditure fell by \(AustralianMoneyFormatter.format(cents: saved)) (-\(String(format: "%.1f", dropPct))%), leaving more surplus for savings.",
                            severity: .positive,
                            supportingEvidence: [
                                "Current flexible spending: \(AustralianMoneyFormatter.format(cents: currentDisc))",
                                "Previous period flexible spending: \(AustralianMoneyFormatter.format(cents: prevDisc))",
                                "Net surplus created: \(AustralianMoneyFormatter.format(cents: saved))"
                            ],
                            supportingTransactionIds: [],
                            significanceScore: 0.8
                        )
                    )
                }
            }
        }

        // 4. Frequent Small Transactions (e.g. coffee, snacks, small top-ups)
        let smallTxs = currentTransactions.filter {
            $0.direction == .debit && $0.amountCents > 0 && $0.amountCents <= 1_500 && // <= $15.00
            $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment
        }
        let totalSmallCents = smallTxs.reduce(MoneyCents(0)) { $0 + $1.amountCents }
        if smallTxs.count >= 10 && totalSmallCents >= 6_000 { // >= 10 txs totalling >= $60
            patterns.append(
                SpendingPattern(
                    type: .frequentSmallTransactions,
                    title: "Frequent Micro-Transactions",
                    summary: "\(smallTxs.count) transactions under $15 added up to \(AustralianMoneyFormatter.format(cents: totalSmallCents)) this period.",
                    severity: .neutral,
                    supportingEvidence: [
                        "Count of transactions ≤ $15.00: \(smallTxs.count)",
                        "Cumulative micro-spend: \(AustralianMoneyFormatter.format(cents: totalSmallCents))",
                        "Average micro-transaction: \(AustralianMoneyFormatter.format(cents: totalSmallCents / Int64(smallTxs.count)))"
                    ],
                    supportingTransactionIds: smallTxs.map(\.id),
                    significanceScore: 0.65
                )
            )
        }

        // 5. Unusually Large Purchases (excluding rent/mortgage)
        let nonRentDebits = currentTransactions.filter {
            $0.direction == .debit &&
            $0.category != .rentAndMortgage &&
            $0.kind != .ownAccountTransfer &&
            $0.kind != .creditCardRepayment
        }
        if !nonRentDebits.isEmpty {
            let avgSpend = totalExpensesCents / Int64(max(1, nonRentDebits.count))
            let threshold = max(MoneyCents(40_000), avgSpend * 3) // >= $400 or >= 3x average
            let largePurchases = nonRentDebits.filter { $0.amountCents >= threshold }
            for bigTx in largePurchases.prefix(2) {
                patterns.append(
                    SpendingPattern(
                        type: .unusuallyLargePurchase,
                        title: "Large Expense: \(bigTx.merchantName)",
                        summary: "Recorded a payment of \(AustralianMoneyFormatter.format(cents: bigTx.amountCents)) for \(bigTx.category.displayName).",
                        severity: .neutral,
                        supportingEvidence: [
                            "Transaction amount: \(AustralianMoneyFormatter.format(cents: bigTx.amountCents))",
                            "Date: \(AustralianDateHelper.formatShortDate(bigTx.occurredAt, timeZoneId: "Australia/Sydney"))",
                            "Category: \(bigTx.category.displayName)"
                        ],
                        supportingTransactionIds: [bigTx.id],
                        significanceScore: 0.75
                    )
                )
            }
        }

        // 6. High Merchant Concentration
        if totalExpensesCents > 0, let topMerchant = merchantAnalytics.first {
            if topMerchant.concentrationShare >= 0.30 && topMerchant.totalSpentCents >= 15_000 {
                let pctStr = String(format: "%.1f", topMerchant.concentrationShare * 100.0)
                patterns.append(
                    SpendingPattern(
                        type: .highMerchantConcentration,
                        title: "High Spend at \(topMerchant.merchantName)",
                        summary: "\(topMerchant.merchantName) accounts for \(pctStr)% of total expenditure this period.",
                        severity: .neutral,
                        supportingEvidence: [
                            "Total spent with merchant: \(AustralianMoneyFormatter.format(cents: topMerchant.totalSpentCents))",
                            "Transaction count: \(topMerchant.transactionCount)",
                            "Average per visit: \(AustralianMoneyFormatter.format(cents: topMerchant.averageTransactionCents))"
                        ],
                        supportingTransactionIds: [],
                        significanceScore: 0.7
                    )
                )
            }
        }

        // 7. Transport Shift
        if hasPreviousHistory, let transportItem = categoryAnalytics.first(where: { $0.category == .fuelTollsVehicle || $0.category == .publicTransport }) {
            let change = transportItem.change
            if change.direction == .increased,
               let pct = change.percentageChange, pct >= 25.0,
               change.absoluteChangeCents >= 3_500 {
                patterns.append(
                    SpendingPattern(
                        type: .transportExpenseChange,
                        title: "Transport Costs Increased",
                        summary: "\(transportItem.category.displayName) rose by \(AustralianMoneyFormatter.format(cents: change.absoluteChangeCents)) (+\(String(format: "%.1f", pct))%).",
                        severity: .headsUp,
                        supportingEvidence: [
                            "Current transport: \(AustralianMoneyFormatter.format(cents: transportItem.currentSpendingCents))",
                            "Previous transport: \(AustralianMoneyFormatter.format(cents: transportItem.previousSpendingCents))"
                        ],
                        supportingTransactionIds: [],
                        significanceScore: 0.7
                    )
                )
            }
        }

        // Sort by significance score descending
        patterns.sort { $0.significanceScore > $1.significanceScore }
        return patterns
    }
}
