import SwiftUI
import Charts

// MARK: - Local Convenience Tokens

private extension DaylightTheme {
    static var alert: Color { cautionRed }
}

private extension DaylightTypography {
    static var statMedium: Font { financialAmount(size: 20) }
}

// MARK: - Spending Analytics View & Components

/// The comprehensive Spending Analytics experience within Daylight Money.
/// Grounded in deterministic calculations, emerald glassmorphism visual styling,
/// and fair like-for-like elapsed period comparisons.
public struct SpendingAnalyticsDashboardView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public enum PeriodSelection: Int, CaseIterable, Identifiable {
        case currentMonth = 0
        case previousMonth = 1
        case twoMonthsAgo = 2

        public var id: Int { rawValue }

        public func label(referenceDate: Date, timeZoneId: String) -> String {
            let cal = AustralianDateHelper.calendar(for: timeZoneId)
            let targetDate = cal.date(byAdding: .month, value: -rawValue, to: referenceDate) ?? referenceDate
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_AU")
            fmt.timeZone = cal.timeZone
            fmt.dateFormat = "MMM yyyy"
            return fmt.string(from: targetDate)
        }
    }

    @State private var selectedPeriodIndex: Int = ProcessInfo.processInfo.arguments.contains("-october") ? 1 : 0

    public init(store: DaylightStore) {
        self.store = store
    }

    private var activeAnalytics: MonthlySpendingAnalytics {
        let cal = AustralianDateHelper.calendar(for: store.profile.timeZoneId)
        let targetDate = cal.date(byAdding: .month, value: -selectedPeriodIndex, to: store.referenceDate) ?? store.referenceDate
        let y = cal.component(.year, from: targetDate)
        let m = cal.component(.month, from: targetDate)
        return store.spendingAnalytics(forYear: y, month: m)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
            // Period Selector
            periodPicker

            // 1. Overview Card
            SpendingOverviewCard(analytics: activeAnalytics, store: store)

            // 2. Spending Trends (Weekly Distribution)
            if !activeAnalytics.weeklyBreakdown.isEmpty {
                SpendingTrendsCard(analytics: activeAnalytics)
            }

            // 3. Category Breakdown & Budget Progress
            if !activeAnalytics.categories.isEmpty {
                SpendingCategoryBreakdownCard(analytics: activeAnalytics, store: store)
            }

            // 4. Merchant Analysis
            if !activeAnalytics.topMerchants.isEmpty {
                SpendingMerchantAnalysisCard(analytics: activeAnalytics)
            }

            // 5. Detected Spending Patterns & Evidence
            if !activeAnalytics.detectedPatterns.isEmpty {
                SpendingPatternInsightsCard(patterns: activeAnalytics.detectedPatterns)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-october") {
                selectedPeriodIndex = 1
            }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        DaylightGlassCard {
            HStack(spacing: 8) {
                ForEach(PeriodSelection.allCases) { period in
                    let isSelected = selectedPeriodIndex == period.rawValue
                    let title = period.label(referenceDate: store.referenceDate, timeZoneId: store.profile.timeZoneId)
                    Button {
                        selectedPeriodIndex = period.rawValue
                    } label: {
                        Text(title)
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(isSelected ? DaylightTheme.GlassText.primary : DaylightTheme.GlassText.muted)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? DaylightTheme.Lime.primary.opacity(0.22) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? DaylightTheme.Lime.primary.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}

// MARK: - 1. Spending Overview Card

public struct SpendingOverviewCard: View {
    public let analytics: MonthlySpendingAnalytics
    public let store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        DaylightGlassCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                // Header with Period & Completeness Badge
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(analytics.period.title)
                            .font(DaylightTypography.cardTitle)
                            .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                        Text(analytics.period.isComplete
                             ? "Full monthly billing cycle • \(analytics.period.totalDays) days"
                             : "Active month in progress • Day \(analytics.period.elapsedDays) of \(analytics.period.totalDays)")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    if !analytics.period.isComplete {
                        DaylightBadge(
                            "Day \(analytics.period.elapsedDays)/\(analytics.period.totalDays)",
                            icon: "hourglass",
                            tone: .neutral
                        )
                    } else {
                        DaylightBadge("Complete", icon: "checkmark", tone: .positive)
                    }
                }

                // Equivalent Period Comparison Explainer (if partial month)
                if let comp = analytics.comparisonToPreviousMonth, comp.isEquivalentPeriodComparison {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(DaylightTheme.Lime.primary)
                        Text("Comparing days 1–\(analytics.period.elapsedDays) like-for-like against last month to prevent partial-month bias.")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.GlassText.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DaylightTheme.Lime.primary.opacity(0.08))
                    )
                }

                Divider().opacity(0.15)

                // Key Metrics Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .top),
                        GridItem(.flexible(), alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    // Total Expenses
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Spending")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Text(AustralianMoneyFormatter.format(cents: analytics.totalExpensesCents))
                            .font(DaylightTypography.statMedium)
                            .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))

                        if let comp = analytics.comparisonToPreviousMonth {
                            comparisonBadge(comp)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)

                    // Daily Average Spend
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Average")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Text(AustralianMoneyFormatter.format(cents: analytics.dailyAverageCents))
                            .font(DaylightTypography.statMedium)
                            .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                        Text("over \(analytics.period.elapsedDays) elapsed days")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)

                    // Total Income
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Income")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Text(AustralianMoneyFormatter.format(cents: analytics.cashFlow.totalIncomeCents))
                            .font(DaylightTypography.cardTitle)
                            .foregroundStyle(DaylightTheme.positive)
                        Text("take-home credits")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)

                    // Net Cash Flow
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Net Cash Flow")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        let net = analytics.cashFlow.netCashFlowCents
                        Text(AustralianMoneyFormatter.format(cents: net, showPlusForPositive: true))
                            .font(DaylightTypography.cardTitle)
                            .foregroundStyle(net >= 0 ? DaylightTheme.positive : DaylightTheme.alert)
                        Text(net >= 0 ? "monthly surplus" : "net deficit")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(net >= 0 ? DaylightTheme.positive.opacity(0.8) : DaylightTheme.alert.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                }

                // Sub-metrics: Refunds & Savings contributions
                if analytics.cashFlow.totalRefundsCents > 0 || analytics.cashFlow.totalSavingsContributionsCents > 0 {
                    Divider().opacity(0.15)
                    HStack(spacing: 16) {
                        if analytics.cashFlow.totalRefundsCents > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.Lime.primary)
                                Text("Refunds: \(AustralianMoneyFormatter.format(cents: analytics.cashFlow.totalRefundsCents))")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                        }
                        if analytics.cashFlow.totalSavingsContributionsCents > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "banknote")
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.positive)
                                Text("Savings: \(AustralianMoneyFormatter.format(cents: analytics.cashFlow.totalSavingsContributionsCents))")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                if let rate = analytics.cashFlow.savingsRate {
                                    Text("(\(String(format: "%.1f", rate))%)")
                                        .font(DaylightTypography.finePrint)
                                        .foregroundStyle(DaylightTheme.positive)
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func comparisonBadge(_ comp: SpendingComparison) -> some View {
        HStack(spacing: 4) {
            let icon: String = {
                switch comp.direction {
                case .increased: return "arrow.up.right"
                case .decreased: return "arrow.down.right"
                case .unchanged: return "equal"
                }
            }()
            let tone: Color = {
                switch comp.direction {
                case .increased: return DaylightTheme.alert
                case .decreased: return DaylightTheme.positive
                case .unchanged: return DaylightTheme.GlassText.muted
                }
            }()
            let pctText = comp.percentageChange.map { "\(String(format: "%.1f", abs($0)))%" } ?? "$0"
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text("\(pctText) vs prev (\(comp.comparisonContextLabel))")
                .font(DaylightTypography.finePrint)
        }
        .foregroundStyle(comp.direction == .decreased ? DaylightTheme.positive : DaylightTheme.alert)
    }
}

// MARK: - 2. Spending Trends Card (Weekly)

public struct SpendingTrendsCard: View {
    public let analytics: MonthlySpendingAnalytics
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        DaylightGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                DaylightSectionHeader(
                    title: "Weekly Spending Trajectory",
                    subtitle: "Distribution of expenses across billing weeks"
                )

                // Chart Legend
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DaylightTheme.Lime.primary, DaylightTheme.Emerald.secondary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 8, height: 8)
                        Text("Weekly Spend")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Rectangle()
                            .stroke(DaylightTheme.Lime.mint.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 14, height: 1)
                        Text("Avg \(AustralianMoneyFormatter.format(cents: analytics.dailyAverageCents * 7))/wk")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.Lime.mint)
                    }
                }
                .padding(.vertical, 2)

                // Chart
                Chart {
                    ForEach(analytics.weeklyBreakdown) { week in
                        BarMark(
                            x: .value("Week", week.shortLabel),
                            y: .value("Spend", Double(week.spentCents) / 100.0)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DaylightTheme.Lime.primary, DaylightTheme.Emerald.secondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(6)
                    }

                    // Monthly daily average reference line
                    let avgDollars = Double(analytics.dailyAverageCents * 7) / 100.0
                    RuleMark(y: .value("Weekly Avg", avgDollars))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(DaylightTheme.Lime.mint.opacity(0.55))
                }
                .frame(height: 165)
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(DaylightTheme.border(for: colorScheme).opacity(0.4))
                        AxisValueLabel {
                            if let num = val.as(Double.self) {
                                Text("$\(Int(num))")
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.GlassText.muted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: analytics.weeklyBreakdown.map(\.shortLabel)) { val in
                        if let shortLabel = val.as(String.self),
                           let week = analytics.weeklyBreakdown.first(where: { $0.shortLabel == shortLabel }) {
                            AxisValueLabel {
                                VStack(spacing: 2) {
                                    Text(week.shortLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                                    Text(week.dateRangeLabel)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundStyle(DaylightTheme.GlassText.muted)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .multilineTextAlignment(.center)
                            }
                        }
                    }
                }

                // Table of weekly details
                VStack(spacing: 10) {
                    ForEach(analytics.weeklyBreakdown) { week in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(week.weekLabel)
                                    .font(DaylightTypography.captionMedium.weight(.semibold))
                                    .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                                Text("\(week.dateRangeLabel) • \(week.transactionCount) txns")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AustralianMoneyFormatter.format(cents: week.spentCents))
                                    .font(DaylightTypography.captionMedium.weight(.semibold))
                                    .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                                Text("Avg \(AustralianMoneyFormatter.format(cents: week.dailyAverageCents))/day")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                        }
                        if week.id != analytics.weeklyBreakdown.last?.id {
                            Divider()
                                .background(DaylightTheme.border(for: colorScheme).opacity(0.3))
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - 3. Category Breakdown Card

public struct SpendingCategoryBreakdownCard: View {
    public let analytics: MonthlySpendingAnalytics
    public let store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        DaylightGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                DaylightSectionHeader(
                    title: "Category Breakdown & Budgets",
                    subtitle: "Expenditure, proportions and budget utilisation"
                )

                // High-level category flags (Fastest growing / Highest spending)
                HStack(spacing: 8) {
                    if let highest = analytics.categories.first(where: \.isHighestSpending) {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(DaylightTheme.Lime.primary)
                            Text("Top: \(highest.category.displayName)")
                                .font(DaylightTypography.finePrint)
                                .foregroundStyle(DaylightTheme.GlassText.primary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(DaylightTheme.Lime.primary.opacity(0.12))
                        .cornerRadius(8)
                    }

                    if let fastest = analytics.categories.first(where: \.isFastestGrowing),
                       let pct = fastest.change.percentageChange, pct > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(DaylightTheme.alert)
                            Text("Fastest: \(fastest.category.displayName) (+\(String(format: "%.0f", pct))%)")
                                .font(DaylightTypography.finePrint)
                                .foregroundStyle(DaylightTheme.GlassText.primary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(DaylightTheme.alert.opacity(0.12))
                        .cornerRadius(8)
                    }
                }

                // Proportional horizontal bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(analytics.categories.prefix(6).filter { $0.currentSpendingCents > 0 }) { cat in
                            let width = geo.size.width * CGFloat(cat.shareOfTotalExpenses)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.category.tintColor)
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 8)
                .cornerRadius(4)

                // Category List
                VStack(spacing: 12) {
                    ForEach(analytics.categories) { cat in
                        categoryRow(cat)
                    }
                }
            }
        }
    }

    private func categoryRow(_ cat: CategorySpendingAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: cat.category.symbolName)
                    .foregroundStyle(cat.category.tintColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(cat.category.tintColor.opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cat.category.displayName)
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                        if cat.isApproachingBudget {
                            Text("Near Limit")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DaylightTheme.warning)
                                .padding(.horizontal, 4)
                                .background(DaylightTheme.warning.opacity(0.15))
                                .cornerRadius(4)
                        } else if cat.isExceedingBudget {
                            Text("Over Budget")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DaylightTheme.alert)
                                .padding(.horizontal, 4)
                                .background(DaylightTheme.alert.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    Text("\(cat.transactionCount) txns • \(String(format: "%.1f", cat.shareOfTotalExpenses * 100.0))% of spend")
                        .font(DaylightTypography.finePrint)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AustralianMoneyFormatter.format(cents: cat.currentSpendingCents))
                        .font(DaylightTypography.subheadlineMedium)
                        .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))

                    // MoM change
                    if let pct = cat.change.percentageChange {
                        let arrow = cat.change.direction == .increased ? "↑" : "↓"
                        Text("\(arrow)\(String(format: "%.0f", abs(pct)))% vs prev")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(cat.change.direction == .decreased ? DaylightTheme.positive : DaylightTheme.textSecondary(for: colorScheme))
                    }
                }
            }

            // Budget Progress Bar if budgeted
            if let budgeted = cat.budgetedCents, budgeted > 0, let util = cat.budgetUtilisation {
                VStack(alignment: .leading, spacing: 2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(util > 1.0 ? DaylightTheme.alert : (util >= 0.8 ? DaylightTheme.warning : DaylightTheme.Lime.primary))
                                .frame(width: min(geo.size.width, geo.size.width * CGFloat(util)))
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        let utilPct = Int(util * 100)
                        Text("\(utilPct)% of \(AustralianMoneyFormatter.format(cents: budgeted)) limit")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Spacer()
                        if let remaining = cat.remainingBudgetCents {
                            Text(remaining >= 0 ? "\(AustralianMoneyFormatter.format(cents: remaining)) remaining" : "\(AustralianMoneyFormatter.format(cents: abs(remaining))) over")
                                .font(DaylightTypography.finePrint)
                                .foregroundStyle(remaining >= 0 ? DaylightTheme.GlassText.muted : DaylightTheme.alert)
                        }
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 4. Merchant Analysis Card

public struct SpendingMerchantAnalysisCard: View {
    public let analytics: MonthlySpendingAnalytics
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        DaylightGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                DaylightSectionHeader(
                    title: "Top Merchants & Concentration",
                    subtitle: "Recognised merchant entities and spending frequency"
                )

                // Top merchant concentration callout
                if let top = analytics.topMerchants.first, top.concentrationShare >= 0.20 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.caption)
                            .foregroundStyle(DaylightTheme.Lime.primary)
                        let pct = String(format: "%.1f", top.concentrationShare * 100.0)
                        Text("\(top.merchantName) represents \(pct)% of total expenditure this period.")
                            .font(DaylightTypography.finePrint)
                            .foregroundStyle(DaylightTheme.GlassText.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DaylightTheme.Lime.primary.opacity(0.08))
                    )
                }

                // Merchant List
                VStack(spacing: 10) {
                    ForEach(analytics.topMerchants) { m in
                        HStack(spacing: 10) {
                            Image(systemName: m.primaryCategory.symbolName)
                                .foregroundStyle(m.primaryCategory.tintColor)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(m.primaryCategory.tintColor.opacity(0.14))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.merchantName)
                                    .font(DaylightTypography.subheadlineMedium)
                                    .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                                Text("\(m.transactionCount) orders • Avg \(AustralianMoneyFormatter.format(cents: m.averageTransactionCents))")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AustralianMoneyFormatter.format(cents: m.totalSpentCents))
                                    .font(DaylightTypography.subheadlineMedium)
                                    .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))
                                Text("\(String(format: "%.1f", m.concentrationShare * 100.0))% share")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - 5. Detected Spending Patterns & Evidence

public struct SpendingPatternInsightsCard: View {
    public let patterns: [SpendingPattern]
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        DaylightGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                DaylightSectionHeader(
                    title: "Detected Spending Patterns",
                    subtitle: "Evidence-backed behavioural shifts and anomalies"
                )

                ForEach(patterns) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            let icon: String = {
                                switch p.severity {
                                case .positive: return "arrow.down.heart.fill"
                                case .headsUp: return "exclamationmark.triangle.fill"
                                case .neutral: return "chart.line.uptrend.xyaxis"
                                }
                            }()

                            let tone: FinancialBadgeTone = {
                                switch p.severity {
                                case .positive: return .positive
                                case .headsUp: return .warning
                                case .neutral: return .neutral
                                }
                            }()

                            DaylightBadge(p.title, icon: icon, tone: tone)
                            Spacer()
                        }

                        Text(p.summary)
                            .font(DaylightTypography.subheadline)
                            .foregroundStyle(DaylightTheme.textPrimary(for: colorScheme))

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(p.supportingEvidence, id: \.self) { ev in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(DaylightTheme.Lime.primary)

                                    Text(ev)
                                        .font(DaylightTypography.finePrint)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                }
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 8)

                    if p.id != patterns.last?.id {
                        Divider().opacity(0.15)
                    }
                }
            }
        }
    }
}
