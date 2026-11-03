import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private func dismissActiveDecimalKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

// MARK: - Screen D: Budget Management View

public struct BudgetsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddCategoryBudget = false
    @State private var isEditingExistingCategoryBudget = false
    @State private var showingCommitmentSheet = false
    @State private var editingCommitmentId: UUID? = nil

    @State private var newBudgetCategory: AustralianCategory = .groceries
    @State private var newBudgetPeriodType: PayFrequency = .fortnightly
    @State private var newBudgetDollars: String = "350.00"
    @State private var newBudgetRollover: Bool = false
    @State private var budgetSheetError: String? = nil

    @State private var newCommitmentTitle: String = ""
    @State private var newCommitmentCategory: AustralianCategory = .rentAndMortgage
    @State private var newCommitmentDollars: String = ""
    @State private var newCommitmentFrequency: PayFrequency = .fortnightly
    @State private var newCommitmentDueDate: Date = Date()
    @State private var commitmentSheetError: String? = nil

    @State private var customOverrideDollars: String = ""
    @State private var customCapFeedbackMessage: String? = nil
    @FocusState private var customCapFieldFocused: Bool
    @FocusState private var budgetLimitFieldFocused: Bool
    @FocusState private var commitmentFieldFocused: Bool

    public init(store: DaylightStore) {
        self.store = store
    }

    private var summary: DailyAllowanceSummary {
        store.allowanceSummary
    }

    private var activePeriodLabel: String {
        store.profile.preferredBudgetingMethod == .monthlyFlexible
            ? "Calendar Month"
            : store.profile.payFrequency.displayName
    }

    private var activeTargetFrequency: PayFrequency {
        FinancialCalculationEngine.activeCalculationTargetFrequency(for: store.profile)
    }

    private var effectiveFixedCategorySet: Set<AustralianCategory> {
        FinancialCalculationEngine.effectiveFixedCommitmentCategories(fixedCommitments: store.fixedCommitments)
    }

    private var totalAllocatedFlexibleEnvelopesCents: MoneyCents {
        store.categoryBudgetProgress
            .filter { !effectiveFixedCategorySet.contains($0.category) }
            .reduce(MoneyCents(0)) { $0 + $1.normalizedActivePeriodLimitCents }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                budgetingMethodSelectorCard
                periodOverviewCard
                categoryBudgetsSection
                fixedCommitmentsSection
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Budgets")
        .onAppear {
            syncCustomCapFieldFromProfile()
        }
        .onChange(of: store.activeTenantId) { _, _ in
            syncCustomCapFieldFromProfile()
            customCapFeedbackMessage = nil
        }
        .onChange(of: store.profile.customFlexibleCapCents) { _, _ in
            syncCustomCapFieldFromProfile()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showingCategoriesManagerSheet = true
                } label: {
                    Label("Categories", systemImage: "tag")
                }

                Button {
                    store.showingCalculationExplainer = true
                } label: {
                    Label("Formula", systemImage: "function")
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    customCapFieldFocused = false
                    dismissActiveDecimalKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingAddCategoryBudget) {
            addCategoryBudgetSheet
        }
        .sheet(isPresented: $showingCommitmentSheet) {
            addOrEditFixedCommitmentSheet
        }
    }

    private func syncCustomCapFieldFromProfile() {
        if let cap = store.profile.customFlexibleCapCents {
            customOverrideDollars = AustralianMoneyFormatter.formatEditableDecimal(cents: cap)
        } else {
            customOverrideDollars = ""
        }
    }

    private var defaultCategoryPeriodType: PayFrequency {
        if store.profile.preferredBudgetingMethod == .monthlyFlexible {
            return .monthly
        }
        switch store.profile.payFrequency {
        case .weekly: return .weekly
        case .fortnightly: return .fortnightly
        case .monthly: return .monthly
        case .irregular: return .fortnightly
        }
    }

    private func categoryPeriodUnitLabel(_ period: PayFrequency) -> String {
        switch period {
        case .weekly: return "Week"
        case .fortnightly: return "Fortnight"
        case .monthly: return "Month"
        case .irregular: return "28 Days"
        }
    }

    private func populateCategoryBudgetDraft(for category: AustralianCategory) {
        newBudgetCategory = category
        if let existing = store.categoryBudgets.first(where: { $0.category == category }) {
            switch existing.periodType {
            case .weekly, .fortnightly, .monthly:
                newBudgetPeriodType = existing.periodType
                newBudgetDollars = AustralianMoneyFormatter.formatEditableDecimal(cents: existing.limitCents)
            case .irregular:
                newBudgetPeriodType = defaultCategoryPeriodType
                let progLimit = store.categoryBudgetProgress.first(where: { $0.category == category })?.baseLimitCents ?? existing.limitCents
                newBudgetDollars = AustralianMoneyFormatter.formatEditableDecimal(cents: progLimit)
            }
            newBudgetRollover = existing.rolloverEnabled
        } else {
            newBudgetPeriodType = defaultCategoryPeriodType
            newBudgetDollars = "350.00"
            newBudgetRollover = store.profile.enableBudgetRollover
        }
    }

    private func openAddCategoryBudgetSheet() {
        isEditingExistingCategoryBudget = false
        budgetSheetError = nil
        populateCategoryBudgetDraft(for: .groceries)
        showingAddCategoryBudget = true
    }

    private func openAddFixedCommitmentSheet() {
        editingCommitmentId = nil
        commitmentSheetError = nil
        newCommitmentTitle = ""
        newCommitmentCategory = .rentAndMortgage
        newCommitmentDollars = ""
        newCommitmentFrequency = store.profile.preferredBudgetingMethod == .monthlyFlexible ? .monthly : store.profile.payFrequency
        newCommitmentDueDate = store.referenceDate
        showingCommitmentSheet = true
    }

    private func openEditFixedCommitmentSheet(_ item: FixedCommitment) {
        editingCommitmentId = item.id
        commitmentSheetError = nil
        newCommitmentTitle = item.title
        newCommitmentCategory = item.category
        newCommitmentDollars = AustralianMoneyFormatter.formatEditableDecimal(cents: item.amountCents)
        newCommitmentFrequency = item.frequency
        newCommitmentDueDate = item.nextDueDate
        showingCommitmentSheet = true
    }

    private var budgetingMethodSelectorCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DaylightBadge("6 Supported Budgeting Methods", icon: "slider.horizontal.3", tone: .neutral)
                    Spacer()
                    Text("Cycle: \(activePeriodLabel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Budgeting Method")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Menu {
                        ForEach(BudgetingMethod.allCases) { method in
                            Button {
                                var p = store.profile
                                p.tenantId = store.activeTenantId
                                p.preferredBudgetingMethod = method
                                try? store.updateProfile(p)
                                customCapFeedbackMessage = nil
                            } label: {
                                if method == store.profile.preferredBudgetingMethod {
                                    Label(method.displayName, systemImage: "checkmark")
                                } else {
                                    Text(method.displayName)
                                }
                            }
                        }
                    } label: {
                        DaylightDropdownPill(store.profile.preferredBudgetingMethod.displayName, icon: "slider.horizontal.3")
                    }
                }

                Text(store.profile.preferredBudgetingMethod.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if store.profile.preferredBudgetingMethod == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Custom Period Flexible Cap (AUD)", text: $customOverrideDollars)
                                .textFieldStyle(.roundedBorder)
                                .focused($customCapFieldFocused)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Button("Apply Cap") {
                                customCapFieldFocused = false
                                dismissActiveDecimalKeyboard()
                                if let cents = AustralianMoneyFormatter.parseToCents(customOverrideDollars), cents >= 0 {
                                    var p = store.profile
                                    p.tenantId = store.activeTenantId
                                    p.customFlexibleCapCents = cents
                                    try? store.updateProfile(p)
                                    customCapFeedbackMessage = "Applied custom flexible cap of \(AustralianMoneyFormatter.format(cents: cents)) for this \(summary.totalDaysInPeriod)-day period."
                                } else {
                                    customCapFeedbackMessage = "Enter a valid non-negative AUD amount (e.g. 1200.00)."
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DaylightTheme.accent)
                        }

                        if let feedback = customCapFeedbackMessage {
                            Text(feedback)
                                .font(.caption)
                                .foregroundStyle(DaylightTheme.accent)
                        }
                    }
                }
            }
        }
    }

    private var periodOverviewCard: some View {
        let ratio: Double = {
            if summary.totalFlexibleBudgetForPeriodCents > 0 {
                return min(1.0, max(0.0, Double(summary.totalFlexibleSpentInPeriodCents) / Double(summary.totalFlexibleBudgetForPeriodCents)))
            }
            return summary.totalFlexibleSpentInPeriodCents > 0 ? 1.0 : 0.0
        }()

        return DaylightGlassCard(
            padding: DaylightTheme.Spacing.md,
            cornerRadius: DaylightTheme.Radius.lg,
            isElevated: true
        ) {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Period Summary (\(summary.totalDaysInPeriod) Days)")
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text("\(AustralianDateHelper.formatMediumDate(summary.periodStart, timeZoneId: store.profile.timeZoneId)) – \(AustralianDateHelper.formatMediumDate(summary.periodEnd, timeZoneId: store.profile.timeZoneId)) • \(summary.remainingDaysInPeriod) day\(summary.remainingDaysInPeriod == 1 ? "" : "s") left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        store.showingCalculationExplainer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DaylightTheme.accent)
                            .frame(width: 40, height: 40, alignment: .center)
                            .background(
                                Circle()
                                    .fill(DaylightTheme.sageSurface(for: colorScheme))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        DaylightTheme.accent.opacity(colorScheme == .dark ? 0.28 : 0.18),
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View active period budget formula")
                }

                GeometryReader { geometry in
                    Capsule(style: .continuous)
                        .fill(DaylightTheme.dividerColor)
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(summary.remainingFlexibleBudgetForPeriodCents < 0 ? DaylightTheme.cautionRed : DaylightTheme.positive)
                                .frame(width: geometry.size.width * ratio)
                        }
                }
                .frame(height: 6)
                .clipShape(Capsule(style: .continuous))

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DaylightTheme.Spacing.sm, alignment: .top),
                        GridItem(.flexible(), spacing: DaylightTheme.Spacing.sm, alignment: .top)
                    ],
                    spacing: DaylightTheme.Spacing.sm
                ) {
                    statBlock(
                        "Flexible Budgeted",
                        cents: summary.totalFlexibleBudgetForPeriodCents,
                        tone: .budget
                    )
                    statBlock(
                        "Flexible Spent",
                        cents: summary.totalFlexibleSpentInPeriodCents,
                        tone: .budget
                    )
                    statBlock(
                        "Flexible Remaining",
                        cents: summary.remainingFlexibleBudgetForPeriodCents,
                        highlightNegative: true,
                        tone: .budget
                    )
                    statBlock(
                        "Estimated Period Spend",
                        cents: summary.forecastEndOfPeriodFlexibleSpendCents,
                        tone: .budget
                    )
                }

                Divider()
                    .opacity(0.35)

                // Progressive disclosure: Cash-flow & envelope reconciliation available on demand
                DisclosureGroup("View cash-flow derivation") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "Income \(AustralianMoneyFormatter.format(cents: summary.periodTakeHomeIncomeCents)) − Fixed Bills \(AustralianMoneyFormatter.format(cents: summary.totalFixedCommitmentsForPeriodCents)) − Savings \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents)) • Safe-to-Spend today: \(AustralianMoneyFormatter.format(cents: summary.todaysRemainingAllowanceCents))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                        if totalAllocatedFlexibleEnvelopesCents > 0 && summary.totalFlexibleBudgetForPeriodCents > 0 {
                            let unallocatedDiff = summary.totalFlexibleBudgetForPeriodCents - totalAllocatedFlexibleEnvelopesCents
                            if unallocatedDiff >= 0 {
                                Text(
                                    "Envelope allocation: \(AustralianMoneyFormatter.format(cents: totalAllocatedFlexibleEnvelopesCents)) allocated across categories • \(AustralianMoneyFormatter.format(cents: unallocatedDiff)) unallocated buffer."
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            } else {
                                Text(
                                    "Envelope notice: Category limits (\(AustralianMoneyFormatter.format(cents: totalAllocatedFlexibleEnvelopesCents))) exceed your period budget by \(AustralianMoneyFormatter.format(cents: abs(unallocatedDiff)))."
                                )
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(DaylightTheme.warning)
                                .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private enum StatTone {
        case budget
        case spent
        case remaining
        case negative
        case forecast

        var color: Color {
            switch self {
            case .budget: return Color(red: 88 / 255, green: 174 / 255, blue: 166 / 255)
            case .spent: return Color(red: 224 / 255, green: 166 / 255, blue: 76 / 255)
            case .remaining: return DaylightTheme.positive
            case .negative: return DaylightTheme.cautionRed
            case .forecast: return Color(red: 157 / 255, green: 133 / 255, blue: 207 / 255)
            }
        }
    }

    private func statBlock(
        _ label: String,
        cents: MoneyCents,
        highlightNegative: Bool = false,
        tone: StatTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DaylightTypography.caption)
                .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
            Text(AustralianMoneyFormatter.format(cents: cents))
                .font(DaylightTypography.financialAmount(size: 17, weight: .bold))
                .foregroundStyle(highlightNegative && cents < 0 ? DaylightTheme.negative : DaylightTheme.primaryText(for: colorScheme))
        }
        .padding(DaylightTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .fill(
                    colorScheme == .dark
                        ? tone.color.opacity(0.13)
                        : tone.color.opacity(0.08)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .strokeBorder(
                    tone.color.opacity(colorScheme == .dark ? 0.26 : 0.20),
                    lineWidth: 1
                )
        )
    }

    private var categoryBudgetsSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            DaylightSectionHeader(
                title: "Category Limits",
                subtitle: "Normalized to your active \(summary.totalDaysInPeriod)-day period • Tap a category's transactions to inspect",
                trailingTitle: "+ Add Category"
            ) {
                openAddCategoryBudgetSheet()
            }

            if store.categoryBudgetProgress.isEmpty {
                DaylightEmptyState(
                    icon: "chart.pie",
                    title: "You haven't set a category budget yet",
                    message: "Set flexible category limits and stay on track daily.",
                    actionTitle: "Set Up First Category"
                ) {
                    openAddCategoryBudgetSheet()
                }
            } else {
                ForEach(store.categoryBudgetProgress) { prog in
                    DaylightCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: prog.category.symbolName)
                                    .foregroundStyle(prog.category.tintColor)
                                Text(prog.category.displayName)
                                    .font(DaylightTypography.cardTitle)
                                Spacer()
                                let pct = Int(round(prog.percentageUsed * 100))
                                DaylightBadge(
                                    prog.isOverBudget ? "\(pct)% (Over Target)" : "\(pct)% Used",
                                    icon: prog.isOverBudget ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                                    tone: prog.isOverBudget ? .overBudget : (prog.percentageUsed > 0.8 ? .warning : .positive)
                                )
                            }

                            ProgressView(value: min(1.0, max(0.0, prog.percentageUsed)))
                                .tint(prog.isOverBudget ? DaylightTheme.negative : (prog.percentageUsed > 0.8 ? DaylightTheme.warning : DaylightTheme.positive))

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Spent: \(AustralianMoneyFormatter.format(cents: prog.netSpentCents)) of \(AustralianMoneyFormatter.format(cents: prog.budgetedCents)) / \(categoryPeriodUnitLabel(prog.sourcePeriodType))")
                                        .font(DaylightTypography.subheadlineMedium)
                                        .monospacedDigit()

                                    let rolloverPart = prog.rolloverAppliedCents != 0
                                        ? " (\(AustralianMoneyFormatter.format(cents: prog.rolloverAppliedCents, showPlusForPositive: true)) rollover)"
                                        : ""
                                    Text("Cadence: \(AustralianMoneyFormatter.format(cents: prog.baseLimitCents)) \(prog.sourcePeriodType.displayName)\(rolloverPart)")
                                        .font(DaylightTypography.caption)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                        .monospacedDigit()

                                    Text("Expected end-of-period: \(AustralianMoneyFormatter.format(cents: prog.projectedEndOfPeriodCents))")
                                        .font(DaylightTypography.caption)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                        .monospacedDigit()
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(prog.remainingCents >= 0 ? "\(AustralianMoneyFormatter.format(cents: prog.remainingCents)) left" : "\(AustralianMoneyFormatter.format(cents: abs(prog.remainingCents))) over")
                                        .font(DaylightTypography.financialAmount(size: 15, weight: .bold))
                                        .foregroundStyle(prog.remainingCents >= 0 ? DaylightTheme.positive : DaylightTheme.negative)

                                    HStack(spacing: 8) {
                                        Button("Edit Limit") {
                                            isEditingExistingCategoryBudget = true
                                            budgetSheetError = nil
                                            populateCategoryBudgetDraft(for: prog.category)
                                            showingAddCategoryBudget = true
                                        }
                                        .font(.caption.weight(.semibold))

                                        Button("View \(prog.recentTransactions.count) Txns") {
                                            store.transactionCategoryDrilldown = prog.category
                                            store.selectedSection = .transactions
                                        }
                                        .font(.caption.weight(.semibold))

                                        if let existing = store.categoryBudgets.first(where: { $0.category == prog.category }) {
                                            Button(role: .destructive) {
                                                store.deleteCategoryBudget(id: existing.id)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                }
                            }

                            if prog.isOverBudget {
                                Text("Overspending in \(prog.category.displayName) is automatically absorbed into your remaining period flexible pool so your daily Safe-to-Spend target stays accurate.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var fixedCommitmentsSection: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                DaylightSectionHeader(
                    title: "Reserved Fixed Commitments",
                    subtitle: "Accounted for before spendable balance",
                    trailingTitle: "+ Add Fixed Bill"
                ) {
                    openAddFixedCommitmentSheet()
                }

                if store.fixedCommitments.isEmpty {
                    Text("No fixed commitments yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.fixedCommitments) { item in
                        let normalizedForPeriodCents = FinancialCalculationEngine.normalizedAmountForCalculation(
                            amountCents: item.amountCents,
                            from: item.frequency,
                            to: activeTargetFrequency
                        )
                        HStack {
                            Image(systemName: item.category.symbolName)
                                .foregroundStyle(item.category.tintColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(DaylightTypography.bodyMedium)
                                Text("\(item.category.displayName) • \(item.frequency.displayName) • Next due \(AustralianDateHelper.formatShortDate(item.nextDueDate, timeZoneId: store.profile.timeZoneId))")
                                    .font(DaylightTypography.caption)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AustralianMoneyFormatter.format(cents: item.amountCents))
                                    .font(DaylightTypography.financialAmount(size: 15, weight: .bold))
                                if normalizedForPeriodCents != item.amountCents {
                                    Text("\(AustralianMoneyFormatter.format(cents: normalizedForPeriodCents)) / \(summary.totalDaysInPeriod)d period")
                                        .font(DaylightTypography.finePrint)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                        .monospacedDigit()
                                }
                            }
                            Button {
                                openEditFixedCommitmentSheet(item)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(item.title)")

                            Button(role: .destructive) {
                                store.deleteFixedCommitment(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(item.title)")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    HStack {
                        Text("Period Fixed Reserve (\(summary.totalDaysInPeriod) days)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(AustralianMoneyFormatter.format(cents: summary.totalFixedCommitmentsForPeriodCents)) total • \(AustralianMoneyFormatter.format(cents: summary.unpaidFixedCommitmentsRemainingCents)) unpaid left")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    ForEach(summary.reconciliationNotices) { notice in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(DaylightTheme.accent)
                            Text(notice.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var addCategoryBudgetSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Category")
                        Spacer()
                        Menu {
                            ForEach(AustralianCategory.expenseCategories) { cat in
                                Button {
                                    populateCategoryBudgetDraft(for: cat)
                                } label: {
                                    if cat == newBudgetCategory {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(newBudgetCategory.displayName, icon: newBudgetCategory.symbolName)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Period")
                            .font(.subheadline)
                        Picker("Time Period", selection: $newBudgetPeriodType) {
                            Text("Weekly").tag(PayFrequency.weekly)
                            Text("Fortnight").tag(PayFrequency.fortnightly)
                            Text("Month").tag(PayFrequency.monthly)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 2)

                    TextField("Base Limit per \(categoryPeriodUnitLabel(newBudgetPeriodType)) in AUD (e.g. 380.00)", text: $newBudgetDollars)
                        .focused($budgetLimitFieldFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif

                    if let parsedCents = AustralianMoneyFormatter.parseToCents(newBudgetDollars), parsedCents > 0 {
                        HStack {
                            Text("Selected category limit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(AustralianMoneyFormatter.format(cents: parsedCents)) / \(categoryPeriodUnitLabel(newBudgetPeriodType))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DaylightTheme.accent)
                                .monospacedDigit()
                        }
                    }

                    Toggle("Enable Unspent Rollover to Next Period", isOn: $newBudgetRollover)
                } footer: {
                    if effectiveFixedCategorySet.contains(newBudgetCategory) {
                        Text("\(newBudgetCategory.displayName) is a fixed-bill category. It stays tracked per \(categoryPeriodUnitLabel(newBudgetPeriodType)) as entered and is reserved in Safe-to-Spend without double-counting.")
                    } else {
                        Text("Your category limit stays displayed and tracked per \(categoryPeriodUnitLabel(newBudgetPeriodType)) exactly as entered.")
                    }
                }

                if let error = budgetSheetError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(DaylightTheme.cautionRed)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditingExistingCategoryBudget ? "Edit Category Limit" : "Set Category Limit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddCategoryBudget = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budgetLimitFieldFocused = false
                        dismissActiveDecimalKeyboard()
                        if let cents = AustralianMoneyFormatter.parseToCents(newBudgetDollars), cents > 0 {
                            store.upsertCategoryBudget(
                                category: newBudgetCategory,
                                limitCents: cents,
                                rolloverEnabled: newBudgetRollover,
                                periodType: newBudgetPeriodType
                            )
                            showingAddCategoryBudget = false
                        } else {
                            budgetSheetError = "Please enter a positive AUD limit greater than $0.00."
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        budgetLimitFieldFocused = false
                        dismissActiveDecimalKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var addOrEditFixedCommitmentSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Commitment Name (e.g. Rent, Strata, Childcare)", text: $newCommitmentTitle)

                    HStack {
                        Text("Category")
                        Spacer()
                        Menu {
                            ForEach(AustralianCategory.expenseCategories) { cat in
                                Button {
                                    newCommitmentCategory = cat
                                } label: {
                                    if cat == newCommitmentCategory {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(newCommitmentCategory.displayName, icon: newCommitmentCategory.symbolName)
                        }
                    }

                    TextField("Amount in AUD (e.g. 920.00)", text: $newCommitmentDollars)
                        .focused($commitmentFieldFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif

                    HStack {
                        Text("Frequency")
                        Spacer()
                        Menu {
                            ForEach(PayFrequency.allCases) { freq in
                                Button {
                                    newCommitmentFrequency = freq
                                } label: {
                                    if freq == newCommitmentFrequency {
                                        Label(freq.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(freq.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(newCommitmentFrequency.displayName, icon: "repeat")
                        }
                    }

                    DatePicker("Next Due Date", selection: $newCommitmentDueDate, displayedComponents: [.date])
                } footer: {
                    Text("Confirmed commitments in \(newCommitmentCategory.displayName) are reserved up-front for the active period and reconciled against matching payments so the same bill is never subtracted twice.")
                }

                if let error = commitmentSheetError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(DaylightTheme.cautionRed)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editingCommitmentId == nil ? "Add Fixed Commitment" : "Edit Fixed Commitment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCommitmentSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCommitmentId == nil ? "Add" : "Save") {
                        commitmentFieldFocused = false
                        dismissActiveDecimalKeyboard()
                        let cleanTitle = newCommitmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanTitle.isEmpty else {
                            commitmentSheetError = "Please enter a name for this fixed commitment."
                            return
                        }
                        guard let cents = AustralianMoneyFormatter.parseToCents(newCommitmentDollars), cents > 0 else {
                            commitmentSheetError = "Please enter a positive AUD amount greater than $0.00."
                            return
                        }
                        if let existingId = editingCommitmentId {
                            store.updateFixedCommitment(
                                id: existingId,
                                title: cleanTitle,
                                category: newCommitmentCategory,
                                amountCents: cents,
                                frequency: newCommitmentFrequency,
                                nextDueDate: newCommitmentDueDate
                            )
                        } else {
                            store.addFixedCommitment(
                                title: cleanTitle,
                                category: newCommitmentCategory,
                                amountCents: cents,
                                frequency: newCommitmentFrequency,
                                nextDueDate: newCommitmentDueDate
                            )
                        }
                        showingCommitmentSheet = false
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        commitmentFieldFocused = false
                        dismissActiveDecimalKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Screen E: Bills & Subscriptions View

public struct BillsAndSubscriptionsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddBillSheet = false
    @State private var billMerchant = ""
    @State private var billCategory: AustralianCategory = .streamingSubscriptions
    @State private var billAmountDollars = ""
    @State private var billFrequency: RecurringFrequency = .monthly
    @State private var billNextDate = Date()
    @State private var billRail = "Direct Debit"
    @State private var billSheetError: String? = nil
    @FocusState private var billAmountFocused: Bool

    public init(store: DaylightStore) {
        self.store = store
    }

    private var confirmedBills: [RecurringPaymentPrediction] {
        store.recurringPredictions.filter { $0.isConfirmedByUser }
    }

    private var predictedBills: [RecurringPaymentPrediction] {
        store.recurringPredictions.filter { !$0.isConfirmedByUser }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                DaylightCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            DaylightBadge("Recurring Commitment Engine", icon: "calendar.badge.clock", tone: .neutral)
                            Spacer()
                        }
                        Text("Confirmed Scheduled Payments vs Predicted Bills")
                            .font(.headline)
                        Text("Detect recurring bills, update forecasts, and manage cancellations through your bank or merchant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DaylightCard {
                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                        DaylightSectionHeader(
                            title: "Confirmed Scheduled Bills (\(confirmedBills.count))",
                            subtitle: "Verified commitments factored into upcoming cash-flow checks",
                            trailingTitle: "+ Add Scheduled Bill"
                        ) {
                            billSheetError = nil
                            showingAddBillSheet = true
                        }

                        if confirmedBills.isEmpty {
                            Text("No confirmed bills yet. Confirm a detected pattern below or add one manually.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(confirmedBills) { bill in
                                billRow(bill, isConfirmedSection: true)
                                Divider()
                            }
                        }
                    }
                }

                DaylightCard {
                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                        DaylightSectionHeader(
                            title: "Detected Recurring Predictions (\(predictedBills.count))",
                            subtitle: "Identified from historical payment intervals & amounts"
                        )

                        if predictedBills.isEmpty {
                            Text("All detected recurring expenses have been reviewed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(predictedBills) { bill in
                                billRow(bill, isConfirmedSection: false)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Bills & Subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    billSheetError = nil
                    showingAddBillSheet = true
                } label: {
                    Label("Add Bill", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddBillSheet) {
            NavigationStack {
                Form {
                    TextField("Merchant / Biller (e.g. Origin Energy, Kayo)", text: $billMerchant)
                    HStack {
                        Text("Category")
                        Spacer()
                        Menu {
                            ForEach(AustralianCategory.expenseCategories) { cat in
                                Button {
                                    billCategory = cat
                                } label: {
                                    if cat == billCategory {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(billCategory.displayName, icon: billCategory.symbolName)
                        }
                    }
                    TextField("Expected Amount in AUD (e.g. 89.00)", text: $billAmountDollars)
                        .focused($billAmountFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    HStack {
                        Text("Frequency")
                        Spacer()
                        Menu {
                            ForEach(RecurringFrequency.allCases) { f in
                                Button {
                                    billFrequency = f
                                } label: {
                                    if f == billFrequency {
                                        Label(f.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(f.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(billFrequency.displayName, icon: "repeat")
                        }
                    }
                    TextField("Payment Rail (BPAY, Direct Debit, Osko, Card)", text: $billRail)
                    DatePicker("Next Expected Date", selection: $billNextDate, displayedComponents: [.date])

                    if let error = billSheetError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(DaylightTheme.cautionRed)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Add Scheduled Bill")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddBillSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            billAmountFocused = false
                            dismissActiveDecimalKeyboard()
                            guard !billMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                billSheetError = "Please enter a merchant or biller name."
                                return
                            }
                            guard let cents = AustralianMoneyFormatter.parseToCents(billAmountDollars), cents > 0 else {
                                billSheetError = "Please enter a positive AUD amount greater than $0.00."
                                return
                            }
                            store.addConfirmedRecurringBill(
                                merchantName: billMerchant,
                                category: billCategory,
                                expectedAmountCents: cents,
                                frequency: billFrequency,
                                nextExpectedDate: billNextDate,
                                paymentRail: billRail
                            )
                            showingAddBillSheet = false
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            billAmountFocused = false
                            dismissActiveDecimalKeyboard()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func billRow(_ bill: RecurringPaymentPrediction, isConfirmedSection: Bool) -> some View {
        HStack(alignment: .top, spacing: DaylightTheme.Spacing.sm) {
            Image(systemName: bill.category.symbolName)
                .foregroundStyle(bill.category.tintColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(bill.category.tintColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bill.merchantName)
                        .font(DaylightTypography.bodyMedium)
                    DaylightBadge(
                        bill.confidence.displayName,
                        icon: bill.isConfirmedByUser ? "checkmark.seal.fill" : "waveform.path.ecg",
                        tone: bill.isConfirmedByUser ? .positive : .neutral
                    )
                }

                Text("Next expected: \(AustralianDateHelper.formatMediumDate(bill.nextExpectedDate, timeZoneId: store.profile.timeZoneId)) • \(bill.frequency.displayName) • \(bill.paymentRail)")
                    .font(DaylightTypography.caption)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))

                Text("Last payment: \(AustralianDateHelper.formatShortDate(bill.lastPaymentDate, timeZoneId: store.profile.timeZoneId)) • Linked evidence: \(max(1, bill.linkedTransactionIds.count)) txn(s)")
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))

                if !isConfirmedSection {
                    HStack(spacing: 10) {
                        Button("Confirm Schedule") {
                            store.confirmRecurringPrediction(id: bill.id)
                        }
                        .font(DaylightTypography.captionMedium)
                        .buttonStyle(.borderedProminent)
                        .tint(DaylightTheme.positive)

                        Button("Dismiss Suggestion", role: .destructive) {
                            store.dismissRecurringPrediction(id: bill.id)
                        }
                        .font(DaylightTypography.captionMedium)
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(AustralianMoneyFormatter.format(cents: bill.expectedAmountCents))
                    .font(DaylightTypography.financialAmount(size: 15, weight: .bold))

                if isConfirmedSection {
                    Button("Remove", role: .destructive) {
                        store.dismissRecurringPrediction(id: bill.id)
                    }
                    .font(DaylightTypography.finePrint)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Screen F: Savings Goals View

public struct SavingsGoalsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddGoal = false
    @State private var selectedGoalForContribution: SavingsGoal? = nil
    @State private var selectedGoalForEdit: SavingsGoal? = nil

    @State private var newGoalName = ""
    @State private var newGoalIcon = "lifepreserver.fill"
    @State private var newGoalTargetDollars = "5000.00"
    @State private var newGoalInitialDollars = "0.00"
    @State private var newGoalTargetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var goalSheetError: String? = nil

    @State private var editGoalName = ""
    @State private var editGoalIcon = "lifepreserver.fill"
    @State private var editGoalTargetDollars = "5000.00"
    @State private var editGoalTargetDate = Date()

    @State private var contributionDollars = "250.00"
    @State private var contributionNote = "Payday contribution"
    @State private var contributionLinkedTransactionId: UUID? = nil

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                DaylightCard {
                    VStack(alignment: .leading, spacing: 6) {
                        DaylightBadge("Transparent Savings Planner", icon: "target", tone: .positive)
                        Text("Track Your Goals With Clear Assumptions")
                            .font(.headline)
                    }
                }

                if store.savingsGoals.isEmpty {
                    DaylightEmptyState(
                        icon: "target",
                        title: "Create your first Australian savings goal",
                        message: "Track an Emergency Fund, Holiday, Car, or First Home Deposit with clear payday contribution targets.",
                        actionTitle: "Create Savings Goal"
                    ) {
                        goalSheetError = nil
                        showingAddGoal = true
                    }
                } else {
                    ForEach(store.savingsGoals) { goal in
                        goalCard(goal)
                    }
                }
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Savings Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    goalSheetError = nil
                    showingAddGoal = true
                } label: {
                    Label("New Goal", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            addGoalSheet
        }
        .sheet(item: $selectedGoalForContribution) { goal in
            addContributionSheet(goal)
        }
        .sheet(item: $selectedGoalForEdit) { goal in
            editGoalSheet(goal)
        }
    }

    private func goalCard(_ goal: SavingsGoal) -> some View {
        let ratio = goal.targetAmountCents > 0
            ? min(1.0, max(0.0, Double(goal.currentSavedCents) / Double(goal.targetAmountCents)))
            : 1.0

        // Exact Australian-calendar per-period contribution rounded UP to the cent so target is guaranteed on time
        let suggestedPerCycleCents = FinancialCalculationEngine.suggestedContributionPerPeriodCents(
            for: goal,
            referenceDate: store.referenceDate,
            profile: store.profile
        )
        let cadenceLabel = store.profile.preferredBudgetingMethod == .monthlyFlexible
            ? "Month"
            : store.profile.payFrequency.displayName

        return DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: goal.iconName)
                        .font(.title3)
                        .foregroundStyle(DaylightTheme.positive)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DaylightTheme.positive.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(DaylightTypography.cardTitle)
                        if let targetDate = goal.targetDate {
                            Text("Target date: \(AustralianDateHelper.formatMediumDate(targetDate, timeZoneId: store.profile.timeZoneId))")
                                .font(DaylightTypography.caption)
                                .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        }
                    }

                    Spacer()

                    Button {
                        goalSheetError = nil
                        editGoalName = goal.name
                        editGoalIcon = goal.iconName
                        editGoalTargetDollars = AustralianMoneyFormatter.formatEditableDecimal(cents: goal.targetAmountCents)
                        editGoalTargetDate = goal.targetDate ?? store.referenceDate
                        selectedGoalForEdit = goal
                    } label: {
                        Label("Edit Goal", systemImage: "pencil")
                            .font(DaylightTypography.captionMedium)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        goalSheetError = nil
                        contributionLinkedTransactionId = nil
                        selectedGoalForContribution = goal
                    } label: {
                        Label("Add Amount", systemImage: "plus.circle.fill")
                            .font(DaylightTypography.captionMedium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)
                }

                ProgressView(value: ratio)
                    .tint(DaylightTheme.positive)

                HStack {
                    Text("Saved: \(AustralianMoneyFormatter.format(cents: goal.currentSavedCents)) (\(Int(round(ratio * 100)))%)")
                        .font(DaylightTypography.subheadlineMedium)
                        .monospacedDigit()
                    Spacer()
                    Text("Target: \(AustralianMoneyFormatter.format(cents: goal.targetAmountCents))")
                        .font(DaylightTypography.caption)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        .monospacedDigit()
                }

                if let suggested = suggestedPerCycleCents {
                    Text("Suggested schedule: \(AustralianMoneyFormatter.format(cents: suggested)) per \(cadenceLabel) to reach target on time.")
                        .font(DaylightTypography.captionMedium)
                        .foregroundStyle(DaylightTheme.accent)
                        .monospacedDigit()
                }

                HStack {
                    Text("Assumptions: \(goal.assumptionsNote)")
                        .font(DaylightTypography.finePrint)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteSavingsGoal(id: goal.id)
                    } label: {
                        Label("Delete Goal", systemImage: "trash")
                            .font(DaylightTypography.finePrint)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var goalIconOptions: [(label: String, icon: String)] {
        [
            ("Emergency Buffer", "lifepreserver.fill"),
            ("Holiday & Travel", "airplane.departure"),
            ("Home Deposit", "house.lodge.fill"),
            ("Vehicle / Car", "car.fill"),
            ("Education", "graduationcap.fill")
        ]
    }

    private var addGoalSheet: some View {
        NavigationStack {
            Form {
                TextField("Goal Name (e.g. Emergency Fund, Japan Trip)", text: $newGoalName)
                HStack {
                    Text("Icon")
                    Spacer()
                    let currentLabel = goalIconOptions.first(where: { $0.icon == newGoalIcon })?.label ?? "Emergency Buffer"
                    Menu {
                        ForEach(goalIconOptions, id: \.icon) { item in
                            Button {
                                newGoalIcon = item.icon
                            } label: {
                                Label(item.label, systemImage: item.icon)
                            }
                        }
                    } label: {
                        DaylightDropdownPill(currentLabel, icon: newGoalIcon)
                    }
                }
                TextField("Target Amount in AUD (e.g. 10000.00)", text: $newGoalTargetDollars)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("Already Saved in AUD (e.g. 1500.00)", text: $newGoalInitialDollars)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                DatePicker("Target Date", selection: $newGoalTargetDate, displayedComponents: [.date])

                if let error = goalSheetError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DaylightTheme.cautionRed)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Savings Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddGoal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        dismissActiveDecimalKeyboard()
                        let cleanName = newGoalName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else {
                            goalSheetError = "Please enter a name for your savings goal."
                            return
                        }
                        guard let target = AustralianMoneyFormatter.parseToCents(newGoalTargetDollars), target > 0 else {
                            goalSheetError = "Please enter a positive target amount greater than $0.00."
                            return
                        }
                        let initial = max(0, AustralianMoneyFormatter.parseToCents(newGoalInitialDollars) ?? 0)
                        store.addSavingsGoal(
                            name: cleanName,
                            iconName: newGoalIcon,
                            targetAmountCents: target,
                            initialSavedCents: initial,
                            targetDate: newGoalTargetDate,
                            linkedAccountId: store.accounts.first(where: { $0.accountType == .highInterestSavings })?.id
                        )
                        showingAddGoal = false
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissActiveDecimalKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func editGoalSheet(_ goal: SavingsGoal) -> some View {
        NavigationStack {
            Form {
                TextField("Goal Name", text: $editGoalName)
                HStack {
                    Text("Icon")
                    Spacer()
                    let currentLabel = goalIconOptions.first(where: { $0.icon == editGoalIcon })?.label ?? "Emergency Buffer"
                    Menu {
                        ForEach(goalIconOptions, id: \.icon) { item in
                            Button {
                                editGoalIcon = item.icon
                            } label: {
                                Label(item.label, systemImage: item.icon)
                            }
                        }
                    } label: {
                        DaylightDropdownPill(currentLabel, icon: editGoalIcon)
                    }
                }
                TextField("Target Amount in AUD", text: $editGoalTargetDollars)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                DatePicker("Target Date", selection: $editGoalTargetDate, displayedComponents: [.date])

                if let error = goalSheetError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DaylightTheme.cautionRed)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Savings Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedGoalForEdit = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dismissActiveDecimalKeyboard()
                        let cleanName = editGoalName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else {
                            goalSheetError = "Please enter a name for your savings goal."
                            return
                        }
                        guard let target = AustralianMoneyFormatter.parseToCents(editGoalTargetDollars), target > 0 else {
                            goalSheetError = "Please enter a positive target amount greater than $0.00."
                            return
                        }
                        store.updateSavingsGoal(
                            goalId: goal.id,
                            name: cleanName,
                            iconName: editGoalIcon,
                            targetAmountCents: target,
                            targetDate: editGoalTargetDate
                        )
                        selectedGoalForEdit = nil
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissActiveDecimalKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addContributionSheet(_ goal: SavingsGoal) -> some View {
        let transferTxns = store.transactions.filter { $0.kind == .ownAccountTransfer || $0.category == .ownAccountTransfer }
        return NavigationStack {
            Form {
                Section("Goal: \(goal.name)") {
                    TextField("Contribution Amount in AUD", text: $contributionDollars)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Note", text: $contributionNote)

                    if !transferTxns.isEmpty {
                        HStack {
                            Text("Link Transfer")
                            Spacer()
                            let linkedLabel = transferTxns.first(where: { $0.id == contributionLinkedTransactionId })?.merchantName ?? "Manual Entry"
                            Menu {
                                Button("Manual Entry") {
                                    contributionLinkedTransactionId = nil
                                }
                                ForEach(transferTxns.prefix(15)) { tx in
                                    Button("\(tx.merchantName) (\(AustralianMoneyFormatter.format(cents: tx.amountCents)))") {
                                        contributionLinkedTransactionId = tx.id
                                    }
                                }
                            } label: {
                                DaylightDropdownPill(linkedLabel, icon: "arrow.left.arrow.right")
                            }
                        }
                    }

                    if let error = goalSheetError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(DaylightTheme.cautionRed)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Log Contribution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedGoalForContribution = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        dismissActiveDecimalKeyboard()
                        if let cents = AustralianMoneyFormatter.parseToCents(contributionDollars), cents > 0 {
                            store.addSavingsContribution(
                                goalId: goal.id,
                                amountCents: cents,
                                note: contributionNote,
                                linkedTransactionId: contributionLinkedTransactionId
                            )
                            selectedGoalForContribution = nil
                        } else {
                            goalSheetError = "Please enter a positive contribution amount greater than $0.00."
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissActiveDecimalKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
