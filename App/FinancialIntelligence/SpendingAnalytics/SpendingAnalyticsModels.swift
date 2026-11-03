import Foundation

// MARK: - Analytics Reporting Period

public struct AnalyticsReportingPeriod: Equatable, Hashable, Sendable {
    public enum PeriodType: Equatable, Hashable, Sendable {
        case calendarMonth(year: Int, month: Int)
        case custom(start: Date, end: Date)
        case financialYear(label: String)
    }

    public let type: PeriodType
    public let title: String
    public let startDate: Date
    public let endDateExclusive: Date
    public let elapsedDays: Int
    public let totalDays: Int
    public let isComplete: Bool

    public init(
        type: PeriodType,
        title: String,
        startDate: Date,
        endDateExclusive: Date,
        elapsedDays: Int,
        totalDays: Int,
        isComplete: Bool
    ) {
        self.type = type
        self.title = title
        self.startDate = startDate
        self.endDateExclusive = endDateExclusive
        self.elapsedDays = elapsedDays
        self.totalDays = totalDays
        self.isComplete = isComplete
    }
}

// MARK: - Spending Comparison

public struct SpendingComparison: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case increased = "Increased"
        case decreased = "Decreased"
        case unchanged = "Unchanged"
    }

    public let currentAmountCents: MoneyCents
    public let previousAmountCents: MoneyCents
    public let absoluteChangeCents: MoneyCents
    public let percentageChange: Double? // nil if previousAmountCents == 0
    public let direction: Direction
    public let isEquivalentPeriodComparison: Bool
    public let comparisonContextLabel: String

    public init(
        currentAmountCents: MoneyCents,
        previousAmountCents: MoneyCents,
        isEquivalentPeriodComparison: Bool = false,
        comparisonContextLabel: String = ""
    ) {
        self.currentAmountCents = currentAmountCents
        self.previousAmountCents = previousAmountCents
        let diff = currentAmountCents - previousAmountCents
        self.absoluteChangeCents = diff

        if previousAmountCents > 0 {
            self.percentageChange = (Double(diff) / Double(previousAmountCents)) * 100.0
        } else if previousAmountCents == 0 && currentAmountCents > 0 {
            self.percentageChange = 100.0
        } else {
            self.percentageChange = nil
        }

        if diff > 0 {
            self.direction = .increased
        } else if diff < 0 {
            self.direction = .decreased
        } else {
            self.direction = .unchanged
        }

        self.isEquivalentPeriodComparison = isEquivalentPeriodComparison
        self.comparisonContextLabel = comparisonContextLabel
    }
}

// MARK: - Weekly Spending Analytics

public struct WeeklySpendingAnalytics: Identifiable, Equatable, Sendable {
    public var id: String { "week_\(weekIndex)_\(startDate.timeIntervalSince1970)" }
    public let weekLabel: String
    public let shortLabel: String
    public let dateRangeLabel: String
    public let weekIndex: Int
    public let startDate: Date
    public let endDateExclusive: Date
    public let spentCents: MoneyCents
    public let dailyAverageCents: MoneyCents
    public let transactionCount: Int

    public init(
        weekLabel: String,
        shortLabel: String? = nil,
        dateRangeLabel: String = "",
        weekIndex: Int,
        startDate: Date,
        endDateExclusive: Date,
        spentCents: MoneyCents,
        dailyAverageCents: MoneyCents,
        transactionCount: Int
    ) {
        self.weekLabel = weekLabel
        self.shortLabel = shortLabel ?? "Wk \(weekIndex)"
        self.dateRangeLabel = dateRangeLabel
        self.weekIndex = weekIndex
        self.startDate = startDate
        self.endDateExclusive = endDateExclusive
        self.spentCents = spentCents
        self.dailyAverageCents = dailyAverageCents
        self.transactionCount = transactionCount
    }
}

// MARK: - Category Spending Analytics

public struct CategorySpendingAnalytics: Identifiable, Equatable, Sendable {
    public var id: String { category.rawValue }
    public let category: AustralianCategory
    public let currentSpendingCents: MoneyCents
    public let previousSpendingCents: MoneyCents
    public let change: SpendingComparison
    public let shareOfTotalExpenses: Double // 0.0 to 1.0
    public let budgetedCents: MoneyCents?
    public let budgetUtilisation: Double? // e.g. 0.85 = 85%
    public let remainingBudgetCents: MoneyCents?
    public let historicalMonthlyAverageCents: MoneyCents?
    public let transactionCount: Int

    public var isHighestSpending: Bool
    public var isFastestGrowing: Bool
    public var isDecreasing: Bool
    public var isApproachingBudget: Bool // >= 80% and <= 100%
    public var isExceedingBudget: Bool // > 100%

    public init(
        category: AustralianCategory,
        currentSpendingCents: MoneyCents,
        previousSpendingCents: MoneyCents,
        change: SpendingComparison,
        shareOfTotalExpenses: Double,
        budgetedCents: MoneyCents?,
        budgetUtilisation: Double?,
        remainingBudgetCents: MoneyCents?,
        historicalMonthlyAverageCents: MoneyCents?,
        transactionCount: Int,
        isHighestSpending: Bool = false,
        isFastestGrowing: Bool = false,
        isDecreasing: Bool = false,
        isApproachingBudget: Bool = false,
        isExceedingBudget: Bool = false
    ) {
        self.category = category
        self.currentSpendingCents = currentSpendingCents
        self.previousSpendingCents = previousSpendingCents
        self.change = change
        self.shareOfTotalExpenses = shareOfTotalExpenses
        self.budgetedCents = budgetedCents
        self.budgetUtilisation = budgetUtilisation
        self.remainingBudgetCents = remainingBudgetCents
        self.historicalMonthlyAverageCents = historicalMonthlyAverageCents
        self.transactionCount = transactionCount
        self.isHighestSpending = isHighestSpending
        self.isFastestGrowing = isFastestGrowing
        self.isDecreasing = isDecreasing
        self.isApproachingBudget = isApproachingBudget
        self.isExceedingBudget = isExceedingBudget
    }
}

// MARK: - Merchant Spending Analytics

public struct MerchantSpendingAnalytics: Identifiable, Equatable, Sendable {
    public var id: String { merchantName }
    public let merchantName: String
    public let totalSpentCents: MoneyCents
    public let transactionCount: Int
    public let averageTransactionCents: MoneyCents
    public let concentrationShare: Double // 0.0 to 1.0 of total expenses
    public let previousPeriodSpentCents: MoneyCents?
    public let comparison: SpendingComparison?
    public let primaryCategory: AustralianCategory
    public let largestTransactionCents: MoneyCents
    public let largestTransactionDate: Date?

    public init(
        merchantName: String,
        totalSpentCents: MoneyCents,
        transactionCount: Int,
        averageTransactionCents: MoneyCents,
        concentrationShare: Double,
        previousPeriodSpentCents: MoneyCents?,
        comparison: SpendingComparison?,
        primaryCategory: AustralianCategory,
        largestTransactionCents: MoneyCents,
        largestTransactionDate: Date?
    ) {
        self.merchantName = merchantName
        self.totalSpentCents = totalSpentCents
        self.transactionCount = transactionCount
        self.averageTransactionCents = averageTransactionCents
        self.concentrationShare = concentrationShare
        self.previousPeriodSpentCents = previousPeriodSpentCents
        self.comparison = comparison
        self.primaryCategory = primaryCategory
        self.largestTransactionCents = largestTransactionCents
        self.largestTransactionDate = largestTransactionDate
    }
}

// MARK: - Cash Flow Analytics

public struct CashFlowAnalytics: Equatable, Sendable {
    public let period: AnalyticsReportingPeriod
    public let currency: String
    public let totalIncomeCents: MoneyCents
    public let totalExpensesCents: MoneyCents
    public let totalRefundsCents: MoneyCents
    public let totalSavingsContributionsCents: MoneyCents
    public let netCashFlowCents: MoneyCents
    public let savingsRate: Double? // percentage, e.g. 15.0%

    public init(
        period: AnalyticsReportingPeriod,
        currency: String = "AUD",
        totalIncomeCents: MoneyCents,
        totalExpensesCents: MoneyCents,
        totalRefundsCents: MoneyCents,
        totalSavingsContributionsCents: MoneyCents,
        netCashFlowCents: MoneyCents,
        savingsRate: Double?
    ) {
        self.period = period
        self.currency = currency
        self.totalIncomeCents = totalIncomeCents
        self.totalExpensesCents = totalExpensesCents
        self.totalRefundsCents = totalRefundsCents
        self.totalSavingsContributionsCents = totalSavingsContributionsCents
        self.netCashFlowCents = netCashFlowCents
        self.savingsRate = savingsRate
    }
}

// MARK: - Spending Pattern & Insights

public enum SpendingPatternType: String, Equatable, Sendable {
    case increasingGroceries = "Increasing Groceries"
    case increasingDining = "Increasing Dining & Takeaway"
    case reducedDiscretionary = "Reduced Discretionary"
    case frequentSmallTransactions = "Frequent Small Transactions"
    case unusuallyLargePurchase = "Unusually Large Purchase"
    case transportExpenseChange = "Transport Expense Shift"
    case highMerchantConcentration = "High Merchant Concentration"
    case unusualCategoryActivity = "Unusual Category Activity"
}

public struct SpendingPattern: Identifiable, Equatable, Sendable {
    public var id: UUID
    public let type: SpendingPatternType
    public let title: String
    public let summary: String
    public let severity: InsightSeverity
    public let supportingEvidence: [String]
    public let supportingTransactionIds: [UUID]
    public let significanceScore: Double // 0.0 to 1.0
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        type: SpendingPatternType,
        title: String,
        summary: String,
        severity: InsightSeverity,
        supportingEvidence: [String],
        supportingTransactionIds: [UUID],
        significanceScore: Double,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.severity = severity
        self.supportingEvidence = supportingEvidence
        self.supportingTransactionIds = supportingTransactionIds
        self.significanceScore = significanceScore
        self.detectedAt = detectedAt
    }
}

public struct SpendingInsight: Identifiable, Equatable, Sendable {
    public var id: UUID
    public let title: String
    public let subtitle: String
    public let detail: String
    public let recommendation: String
    public let severity: InsightSeverity
    public let relatedCategory: AustralianCategory?
    public let supportingTransactionIds: [UUID]
    public let metricHeadline: String?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        detail: String,
        recommendation: String,
        severity: InsightSeverity,
        relatedCategory: AustralianCategory? = nil,
        supportingTransactionIds: [UUID] = [],
        metricHeadline: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.recommendation = recommendation
        self.severity = severity
        self.relatedCategory = relatedCategory
        self.supportingTransactionIds = supportingTransactionIds
        self.metricHeadline = metricHeadline
    }
}

// MARK: - Monthly Spending Analytics (Aggregate)

public struct MonthlySpendingAnalytics: Identifiable, Equatable, Sendable {
    public var id: String { period.title }
    public let period: AnalyticsReportingPeriod
    public let currency: String
    public let cashFlow: CashFlowAnalytics
    public let totalExpensesCents: MoneyCents
    public let dailyAverageCents: MoneyCents
    public let comparisonToPreviousMonth: SpendingComparison?
    public let weeklyBreakdown: [WeeklySpendingAnalytics]
    public let categories: [CategorySpendingAnalytics]
    public let topMerchants: [MerchantSpendingAnalytics]
    public let detectedPatterns: [SpendingPattern]
    public let insights: [SpendingInsight]

    public init(
        period: AnalyticsReportingPeriod,
        currency: String = "AUD",
        cashFlow: CashFlowAnalytics,
        totalExpensesCents: MoneyCents,
        dailyAverageCents: MoneyCents,
        comparisonToPreviousMonth: SpendingComparison?,
        weeklyBreakdown: [WeeklySpendingAnalytics],
        categories: [CategorySpendingAnalytics],
        topMerchants: [MerchantSpendingAnalytics],
        detectedPatterns: [SpendingPattern],
        insights: [SpendingInsight]
    ) {
        self.period = period
        self.currency = currency
        self.cashFlow = cashFlow
        self.totalExpensesCents = totalExpensesCents
        self.dailyAverageCents = dailyAverageCents
        self.comparisonToPreviousMonth = comparisonToPreviousMonth
        self.weeklyBreakdown = weeklyBreakdown
        self.categories = categories
        self.topMerchants = topMerchants
        self.detectedPatterns = detectedPatterns
        self.insights = insights
    }
}

// MARK: - Money Story Consumption Model

public struct SpendingIntelligenceSummary: Codable, Identifiable, Equatable, Sendable {
    public var id: String { periodLabel }
    public let periodLabel: String
    public let totalSpentCents: MoneyCents
    public let previousPeriodSpentCents: MoneyCents
    public let spendingChangePercentage: Double?
    public let isEquivalentPeriodComparison: Bool
    public let netCashFlowCents: MoneyCents
    public let topCategoryName: String?
    public let topCategorySpentCents: MoneyCents?
    public let topMerchantName: String?
    public let topMerchantSpentCents: MoneyCents?
    public let keyObservations: [String]
    public let detectedPatternTitles: [String]
    public let budgetAlertCount: Int

    public init(
        periodLabel: String,
        totalSpentCents: MoneyCents,
        previousPeriodSpentCents: MoneyCents,
        spendingChangePercentage: Double?,
        isEquivalentPeriodComparison: Bool,
        netCashFlowCents: MoneyCents,
        topCategoryName: String?,
        topCategorySpentCents: MoneyCents?,
        topMerchantName: String?,
        topMerchantSpentCents: MoneyCents?,
        keyObservations: [String],
        detectedPatternTitles: [String],
        budgetAlertCount: Int
    ) {
        self.periodLabel = periodLabel
        self.totalSpentCents = totalSpentCents
        self.previousPeriodSpentCents = previousPeriodSpentCents
        self.spendingChangePercentage = spendingChangePercentage
        self.isEquivalentPeriodComparison = isEquivalentPeriodComparison
        self.netCashFlowCents = netCashFlowCents
        self.topCategoryName = topCategoryName
        self.topCategorySpentCents = topCategorySpentCents
        self.topMerchantName = topMerchantName
        self.topMerchantSpentCents = topMerchantSpentCents
        self.keyObservations = keyObservations
        self.detectedPatternTitles = detectedPatternTitles
        self.budgetAlertCount = budgetAlertCount
    }
}

extension MonthlySpendingAnalytics {
    public func toMoneyStorySummary() -> SpendingIntelligenceSummary {
        var obs: [String] = []

        if let comp = comparisonToPreviousMonth {
            let pctStr = comp.percentageChange.map { "\(String(format: "%.1f", abs($0)))%" } ?? ""
            if comp.direction == .increased {
                obs.append("Spending increased by \(AustralianMoneyFormatter.format(cents: comp.absoluteChangeCents)) (\(pctStr)) vs \(comp.isEquivalentPeriodComparison ? "equivalent days last month" : "last month").")
            } else if comp.direction == .decreased {
                obs.append("Spending dropped by \(AustralianMoneyFormatter.format(cents: abs(comp.absoluteChangeCents))) (\(pctStr)) vs \(comp.isEquivalentPeriodComparison ? "equivalent days last month" : "last month").")
            }
        }

        let topCat = categories.first(where: \.isHighestSpending) ?? categories.first
        if let topCat, topCat.currentSpendingCents > 0 {
            let pct = String(format: "%.0f", topCat.shareOfTotalExpenses * 100.0)
            obs.append("\(topCat.category.displayName) was your highest spending category (\(AustralianMoneyFormatter.format(cents: topCat.currentSpendingCents)), \(pct)% of total).")
        }

        if let fastGrowing = categories.first(where: \.isFastestGrowing),
           let pct = fastGrowing.change.percentageChange, pct > 0 {
            obs.append("\(fastGrowing.category.displayName) was the fastest growing category (+\(String(format: "%.1f", pct))%).")
        }

        let overBudgetCount = categories.filter { $0.isApproachingBudget || $0.isExceedingBudget }.count
        if overBudgetCount > 0 {
            obs.append("\(overBudgetCount) category budget(s) require attention.")
        }

        for pattern in detectedPatterns.prefix(2) {
            obs.append(pattern.title + ": " + pattern.summary)
        }

        return SpendingIntelligenceSummary(
            periodLabel: period.title,
            totalSpentCents: totalExpensesCents,
            previousPeriodSpentCents: comparisonToPreviousMonth?.previousAmountCents ?? 0,
            spendingChangePercentage: comparisonToPreviousMonth?.percentageChange,
            isEquivalentPeriodComparison: comparisonToPreviousMonth?.isEquivalentPeriodComparison ?? false,
            netCashFlowCents: cashFlow.netCashFlowCents,
            topCategoryName: topCat?.category.displayName,
            topCategorySpentCents: topCat?.currentSpendingCents,
            topMerchantName: topMerchants.first?.merchantName,
            topMerchantSpentCents: topMerchants.first?.totalSpentCents,
            keyObservations: obs,
            detectedPatternTitles: detectedPatterns.map(\.title),
            budgetAlertCount: overBudgetCount
        )
    }
}
