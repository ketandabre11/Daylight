import SwiftUI

/// Plain-language breakdown that connects the user's earnings to their daily spending limit.
///
/// Follows progressive disclosure:
///  1. Primary summary: Always visible, showing today's limit and normal baseline.
///  2. Contextual pace note: Explains variance between today's limit and normal baseline.
///  3. "How is this calculated?": Expandable on demand, showing the step-by-step financial formula.
public struct DailyLimitBreakdownCard: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isCalculatedExpanded: Bool = false
    @State private var showingOtherPayFrequencies: Bool = false

    public init(store: DaylightStore) {
        self.store = store
    }

    private var summary: DailyAllowanceSummary { store.allowanceSummary }
    private var profile: UserProfile { store.profile }

    private func money(_ cents: MoneyCents) -> String {
        AustralianMoneyFormatter.format(cents: cents)
    }

    // MARK: - Derived figures (all taken from the engine's summary)

    private var payEquivalents: [(frequency: PayFrequency, label: String, cents: MoneyCents)] {
        let entered = max(0, profile.typicalTakeHomePayCents)
        let rows: [(PayFrequency, String)] = [(.weekly, "Week"), (.fortnightly, "Fortnight"), (.monthly, "Month")]
        return rows.map { freq, label in
            (freq, label, FinancialCalculationEngine.normalizedAmountForCalculation(
                amountCents: entered, from: profile.payFrequency, to: freq))
        }
    }

    private var yearlyPayCents: MoneyCents {
        max(0, profile.typicalTakeHomePayCents) * MoneyCents(profile.payFrequency.annualCyclesCount)
    }

    /// Income minus bills minus savings, before any custom cap or category-envelope limit.
    private var leftAfterBillsAndSavingsCents: MoneyCents {
        summary.periodTakeHomeIncomeCents
            - summary.totalFixedCommitmentsForPeriodCents
            - summary.plannedSavingsForPeriodCents
    }

    /// True when the budgeting method (custom cap / category envelopes) sets the spending money directly.
    private var spendingMoneyIsCapped: Bool {
        summary.totalFlexibleBudgetForPeriodCents != max(0, leftAfterBillsAndSavingsCents)
    }

    /// Spending recorded for later dates in this period, which is set aside already.
    private var reservedFutureCents: MoneyCents {
        max(0, summary.totalFlexibleSpentInPeriodCents - summary.flexibleSpentPriorToTodayCents - summary.flexibleSpentTodayCents)
    }

    private var spendingMoneyLeftAtStartOfTodayCents: MoneyCents {
        max(0, summary.totalFlexibleBudgetForPeriodCents - summary.flexibleSpentPriorToTodayCents - reservedFutureCents)
    }

    private var periodIncomeWasConverted: Bool {
        summary.periodTakeHomeIncomeCents != profile.typicalTakeHomePayCents
    }

    private var hasSpentToday: Bool {
        summary.flexibleSpentTodayCents != 0
    }

    private var isOverLimitToday: Bool {
        summary.todaysRemainingAllowanceCents < 0
    }

    // MARK: - Body

    public var body: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 12) {
                // A. Primary summary & B. Today's calculation (Always visible)
                primarySummarySection

                // Contextual explanation note (if ahead/behind normal pace)
                contextualPaceNote

                // C. Explain the calculation — Expandable disclosure toggle
                explanationDisclosureButton

                // Grouped detailed calculation (revealed on tap)
                if isCalculatedExpanded {
                    expandedCalculationSection
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your daily spending limit")
    }

    // MARK: - A. Primary Summary & B. Today's Calculation (Always visible)

    private var primarySummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your daily spending limit")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                    Text("Your normal limit is \(money(summary.baselineDailyAllowanceCents))/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !hasSpentToday {
                // Zero spend today: prominent hero starting allowance
                VStack(alignment: .leading, spacing: 2) {
                    Text(money(summary.todaysStartingAllowanceCents))
                        .font(DaylightTypography.financialAmount(size: 34, weight: .bold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                    Text("Available for today")
                        .font(DaylightTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                // Spending recorded today: clear vertical hierarchy distinguishing starting, spent, and remaining
                VStack(spacing: 8) {
                    HStack {
                        Text("Starting allowance")
                            .font(DaylightTypography.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(money(summary.todaysStartingAllowanceCents))
                            .font(DaylightTypography.subheadlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                    }

                    HStack {
                        Text("Spent today")
                            .font(DaylightTypography.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("−\(money(summary.flexibleSpentTodayCents))")
                            .font(DaylightTypography.subheadlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(DaylightTheme.warning)
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isOverLimitToday ? "Over today's limit" : "Left to spend today")
                                .font(DaylightTypography.subheadline.weight(.semibold))
                                .foregroundStyle(isOverLimitToday ? DaylightTheme.negative : DaylightTheme.positive)
                            Text("Remaining today")
                                .font(DaylightTypography.finePrint)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(summary.todaysRemainingAllowanceCents))
                            .font(DaylightTypography.financialAmount(size: 28, weight: .bold))
                            .foregroundStyle(isOverLimitToday ? DaylightTheme.negative : DaylightTheme.positive)
                    }
                }
                .padding(DaylightTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.md)
                        .fill(DaylightTheme.secondarySurface(for: colorScheme).opacity(0.5))
                )
            }
        }
    }

    // MARK: - D. Contextual Explanation (Pace Note)

    @ViewBuilder
    private var contextualPaceNote: some View {
        let difference = summary.todaysStartingAllowanceCents - summary.baselineDailyAllowanceCents
        if abs(difference) > 1 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: difference > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(difference > 0 ? DaylightTheme.positive : DaylightTheme.warning)

                Text(difference > 0
                     ? "Your limit is higher today because you spent less earlier this period (+\(money(difference))/day)."
                     : "Your limit is lower today because earlier spending is spread across the remaining days (−\(money(abs(difference)))/day).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                    .fill((difference > 0 ? DaylightTheme.positive : DaylightTheme.warning).opacity(0.08))
            )
        }
    }

    // MARK: - C. Disclosure Control

    private var explanationDisclosureButton: some View {
        Button {
            if reduceMotion {
                isCalculatedExpanded.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCalculatedExpanded.toggle()
                }
            }
        } label: {
            HStack {
                Text("How is this calculated?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DaylightTheme.accent)

                Spacer()

                Image(systemName: isCalculatedExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DaylightTheme.accent)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCalculatedExpanded ? "Hide calculation breakdown" : "How is this calculated?")
        .accessibilityHint("Double tap to \(isCalculatedExpanded ? "collapse" : "expand") step-by-step financial formula")
    }

    // MARK: - D. Expandable Detailed Calculation

    private var expandedCalculationSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
            Divider()
                .padding(.top, 2)

            // Group 1: Your Pay
            payGroup

            Divider()

            // Group 2: This Period
            periodGroup

            Divider()

            // Group 3: Today
            todayGroup
        }
    }

    // MARK: - Group 1: Your Pay

    private var payGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepHeader(number: 1, title: "Your take-home pay")

            // Primary value: what the user entered
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entered pay")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(money(profile.typicalTakeHomePayCents)) per \(singular(profile.payFrequency))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                }

                Spacer()

                Text("Primary")
                    .font(DaylightTypography.finePrint.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DaylightTheme.accent.opacity(0.12)))
                    .foregroundStyle(DaylightTheme.accent)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                    .fill(DaylightTheme.secondarySurface(for: colorScheme).opacity(0.4))
            )

            // Secondary expandable area for alternative pay frequencies
            DisclosureGroup(isExpanded: $showingOtherPayFrequencies) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(payEquivalents, id: \.frequency) { item in
                            payChip(
                                label: "Per \(item.label)",
                                value: money(item.cents),
                                isEntered: item.frequency == profile.payFrequency
                            )
                        }
                        payChip(label: "Per Year", value: money(yearlyPayCents), isEntered: false)
                    }

                    Text(profile.payFrequency == .irregular
                         ? "You entered \(money(profile.typicalTakeHomePayCents)) per 4-week cycle. Other amounts are the same yearly pay split differently (52 weeks = 26 fortnights = 12 months)."
                         : "You entered \(money(profile.typicalTakeHomePayCents)) per \(singular(profile.payFrequency)). Other amounts are the same yearly pay split differently (52 weeks = 26 fortnights = 12 months).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } label: {
                Text(showingOtherPayFrequencies ? "Hide other pay periods" : "View other pay periods")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DaylightTheme.accent)
            }
        }
    }

    // MARK: - Group 2: This Period

    private var periodGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepHeader(
                number: 2,
                title: "This period",
                trailing: "\(AustralianDateHelper.formatShortDate(summary.periodStart, timeZoneId: profile.timeZoneId)) – \(AustralianDateHelper.formatShortDate(summary.periodEnd, timeZoneId: profile.timeZoneId)) · \(summary.totalDaysInPeriod) days"
            )

            equationRow(
                symbol: "+",
                label: "Income for this period",
                detail: periodIncomeWasConverted
                    ? "Your \(profile.payFrequency.displayName.lowercased()) pay converted to this \(summary.totalDaysInPeriod)-day period"
                    : nil,
                value: money(summary.periodTakeHomeIncomeCents)
            )
            equationRow(symbol: "−", label: "Bills and fixed costs", detail: nil,
                        value: money(summary.totalFixedCommitmentsForPeriodCents))
            equationRow(symbol: "−", label: "Planned savings", detail: nil,
                        value: money(summary.plannedSavingsForPeriodCents))

            Divider().padding(.leading, 28)

            equationRow(
                symbol: "=",
                label: "Spending money",
                detail: spendingMoneyIsCapped
                    ? "Set by your \(summary.budgetingMethodUsed.displayName) limit"
                    : nil,
                value: money(summary.totalFlexibleBudgetForPeriodCents),
                emphasised: true
            )
            equationRow(
                symbol: "÷",
                label: "Days in period (\(summary.totalDaysInPeriod) days)",
                detail: nil,
                value: "\(summary.totalDaysInPeriod) days"
            )

            Divider().padding(.leading, 28)

            equationRow(
                symbol: "=",
                label: "Normal daily limit",
                detail: nil,
                value: "\(money(summary.baselineDailyAllowanceCents))/day",
                emphasised: true,
                highlight: DaylightTheme.accent
            )
        }
    }

    // MARK: - Group 3: Today

    private var todayGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepHeader(
                number: 3,
                title: "Today",
                trailing: "\(summary.remainingDaysInPeriod) day\(summary.remainingDaysInPeriod == 1 ? "" : "s") left"
            )

            equationRow(symbol: "", label: "Spending money", detail: nil,
                        value: money(summary.totalFlexibleBudgetForPeriodCents))
            equationRow(symbol: "−", label: "Previous spending", detail: nil,
                        value: money(summary.flexibleSpentPriorToTodayCents))
            if reservedFutureCents > 0 {
                equationRow(symbol: "−", label: "Amount reserved for later", detail: "Spending recorded for upcoming dates",
                            value: money(reservedFutureCents))
            }

            Divider().padding(.leading, 28)

            equationRow(symbol: "=", label: "Amount available at start of today", detail: nil,
                        value: money(spendingMoneyLeftAtStartOfTodayCents))
            equationRow(
                symbol: "÷",
                label: "Remaining days (\(summary.remainingDaysInPeriod) left)",
                detail: nil,
                value: "\(summary.remainingDaysInPeriod) days"
            )

            Divider().padding(.leading, 28)

            equationRow(
                symbol: "=",
                label: "Today's starting allowance",
                detail: nil,
                value: money(summary.todaysStartingAllowanceCents),
                emphasised: true,
                highlight: DaylightTheme.accent
            )
            equationRow(symbol: "−", label: "Spent today", detail: nil,
                        value: money(summary.flexibleSpentTodayCents))

            Divider().padding(.leading, 28)

            equationRow(
                symbol: "=",
                label: isOverLimitToday ? "Over today's limit" : "Left to spend today",
                detail: nil,
                value: money(summary.todaysRemainingAllowanceCents),
                emphasised: true,
                highlight: isOverLimitToday ? DaylightTheme.cautionRed : DaylightTheme.positive
            )
        }
    }

    // MARK: - Building Blocks

    private func stepHeader(number: Int, title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(DaylightTheme.accent))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func equationRow(
        symbol: String,
        label: String,
        detail: String?,
        value: String,
        emphasised: Bool = false,
        highlight: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Text(value)
                .font(emphasised ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(highlight ?? DaylightTheme.primaryText(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
    }

    private func payChip(label: String, value: String, isEntered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEntered {
                    Text("You entered")
                        .font(DaylightTypography.finePrint.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DaylightTheme.accent.opacity(0.15)))
                        .foregroundStyle(DaylightTheme.accent)
                }
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .fill(isEntered ? DaylightTheme.accent.opacity(0.08) : DaylightTheme.secondarySurface(for: colorScheme).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .strokeBorder(isEntered ? DaylightTheme.accent.opacity(0.35) : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func singular(_ frequency: PayFrequency) -> String {
        switch frequency {
        case .weekly: return "week"
        case .fortnightly: return "fortnight"
        case .monthly: return "month"
        case .irregular: return "4-week cycle"
        }
    }
}
