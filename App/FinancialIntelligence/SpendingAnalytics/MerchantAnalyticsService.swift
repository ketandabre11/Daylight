import Foundation

/// Analyzes merchant-level expenditure, concentration, frequency, and transaction sizes.
public final class MerchantAnalyticsService: Sendable {
    public static let shared = MerchantAnalyticsService()

    public init() {}

    public func analyzeMerchants(
        currentPeriodTransactions: [TransactionRecord],
        previousPeriodTransactions: [TransactionRecord] = [],
        totalExpensesCents: MoneyCents
    ) -> [MerchantSpendingAnalytics] {
        // Group current transactions by merchant name
        var currentMap: [String: [TransactionRecord]] = [:]
        for tx in currentPeriodTransactions {
            guard !tx.excludeFromBudget && tx.status != .reversed else { continue }
            guard tx.kind != .ownAccountTransfer && tx.kind != .creditCardRepayment && tx.kind != .income else { continue }

            // Normalize with recognition service to get canonical name if known
            let merchantKey = tx.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !merchantKey.isEmpty else { continue }
            currentMap[merchantKey, default: []].append(tx)
        }

        // Group previous period transactions for comparison
        var previousMap: [String: MoneyCents] = [:]
        for tx in previousPeriodTransactions {
            guard !tx.excludeFromBudget && tx.status != .reversed else { continue }
            guard tx.kind != .ownAccountTransfer && tx.kind != .creditCardRepayment && tx.kind != .income else { continue }
            let merchantKey = tx.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !merchantKey.isEmpty else { continue }
            let contrib = FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
            if contrib != 0 {
                previousMap[merchantKey, default: 0] += contrib
            }
        }

        var results: [MerchantSpendingAnalytics] = []

        for (merchantName, txs) in currentMap {
            // Net spend contribution taking into account any refunds from this merchant
            var netSpend: MoneyCents = 0
            var debitCount = 0
            var largestTx: TransactionRecord? = nil

            for tx in txs {
                let contrib = FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
                netSpend += contrib

                if tx.direction == .debit {
                    debitCount += 1
                    if largestTx == nil || tx.amountCents > (largestTx?.amountCents ?? 0) {
                        largestTx = tx
                    }
                }
            }

            guard netSpend > 0 else { continue }

            let count = max(1, debitCount)
            let avg = netSpend / Int64(count)
            let concentration = totalExpensesCents > 0
                ? (Double(netSpend) / Double(totalExpensesCents))
                : 0.0

            let prev = previousMap[merchantName]
            let comp: SpendingComparison?
            if let p = prev {
                comp = SpendingComparison(
                    currentAmountCents: netSpend,
                    previousAmountCents: p
                )
            } else {
                comp = nil
            }

            // Most common category for this merchant in these transactions
            var catCounts: [AustralianCategory: Int] = [:]
            for tx in txs {
                catCounts[tx.category, default: 0] += 1
            }
            let primaryCat = catCounts.max { $0.value < $1.value }?.key ?? .cashAndUnclassified

            let item = MerchantSpendingAnalytics(
                merchantName: merchantName,
                totalSpentCents: netSpend,
                transactionCount: txs.count,
                averageTransactionCents: avg,
                concentrationShare: concentration,
                previousPeriodSpentCents: prev,
                comparison: comp,
                primaryCategory: primaryCat,
                largestTransactionCents: largestTx?.amountCents ?? netSpend,
                largestTransactionDate: largestTx?.occurredAt
            )
            results.append(item)
        }

        // Sort by total expenditure descending
        results.sort { $0.totalSpentCents > $1.totalSpentCents }
        return results
    }
}
