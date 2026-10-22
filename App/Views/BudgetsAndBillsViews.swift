import SwiftUI

// MARK: - Screen D: Budget Management View

public struct BudgetsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddCategoryBudget = false
    @State private var showingAddCommitment = false
    @State private var newBudgetCategory: AustralianCategory = .groceries
    @State private var newBudgetDollars: String = "350.00"
    @State private var newBudgetRollover: Bool = false

    @State private var newCommitmentTitle: String = ""
    @State private var newCommitmentCategory: AustralianCategory = .rentAndMortgage
    @State private var newCommitmentDollars: String = ""
    @State private var newCommitmentFrequency: PayFrequency = .fortnightly
    @State private var newCommitmentDueDate: Date = Date()

    @State private var customOverrideDollars: String = ""

    public init(store: DaylightStore) {
        self.store = store
    }

    private var summary: DailyAllowanceSummary {
        store.allowanceSummary
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
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Budgets")
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

                Button {
                    showingAddCategoryBudget = true
                } label: {
                    Label("Add Category Limit", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddCategoryBudget) {
            addCategoryBudgetSheet
        }
        .sheet(isPresented: $showingAddCommitment) {
            addFixedCommitmentSheet
        }
    }

    private var budgetingMethodSelectorCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DaylightBadge("6 Supported Budgeting Methods", icon: "slider.horizontal.3", tone: .neutral)
                    Spacer()
                    Text("Cycle: \(store.profile.payFrequency.displayName)")
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
                                p.preferredBudgetingMethod = method
                                try? store.updateProfile(p)
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
                    HStack {
                        TextField("Custom Period Flexible Cap (AUD)", text: $customOverrideDollars)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Button("Apply Cap") {
                            if let cents = AustralianMoneyFormatter.parseToCents(customOverrideDollars), cents > 0 {
                                var p = store.profile
                                p.customFlexibleCapCents = cents
                                try? store.updateProfile(p)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DaylightTheme.accent)
                    }
                }
            }
        }
    }

    private var periodOverviewCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                DaylightSectionHeader(
                    title: "Active Period Summary (\(summary.totalDaysInPeriod) Days)",
                    subtitle: "\(AustralianDateHelper.formatMediumDate(summary.periodStart, timeZoneId: store.profile.timeZoneId)) – \(AustralianDateHelper.formatMediumDate(summary.periodEnd, timeZoneId: store.profile.timeZoneId))",
                    trailingTitle: "View Formula"
                ) {
                    store.showingCalculationExplainer = true
                }

                let ratio = summary.totalFlexibleBudgetForPeriodCents > 0
                    ? min(1.0, Double(summary.totalFlexibleSpentInPeriodCents) / Double(summary.totalFlexibleBudgetForPeriodCents))
                    : 0.0

                ProgressView(value: ratio)
                    .tint(summary.remainingFlexibleBudgetForPeriodCents < 0 ? DaylightTheme.cautionRed : DaylightTheme.positive)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    statBlock("Flexible Budgeted", cents: summary.totalFlexibleBudgetForPeriodCents)
                    statBlock("Flexible Spent", cents: summary.totalFlexibleSpentInPeriodCents)
                    statBlock("Flexible Remaining", cents: summary.remainingFlexibleBudgetForPeriodCents)
                    statBlock("Expected End-of-Period Spend", cents: summary.forecastEndOfPeriodFlexibleSpendCents)
                }
            }
        }
    }

    private func statBlock(_ label: String, cents: MoneyCents) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AustralianMoneyFormatter.format(cents: cents))
                .font(.headline.weight(.bold))
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var categoryBudgetsSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            DaylightSectionHeader(
                title: "Category Limits & Envelopes",
                subtitle: "Tap a category to inspect underlying transactions",
                trailingTitle: "+ Add Category Limit"
            ) {
                showingAddCategoryBudget = true
            }

            if store.categoryBudgetProgress.isEmpty {
                DaylightEmptyState(
                    icon: "chart.pie",
                    title: "You haven't set a category budget yet",
                    message: "Create category limits for Groceries, Cafes, or Transport to track pacing alongside your daily safe-to-spend allowance.",
                    actionTitle: "Set Up First Category Limit"
                ) {
                    showingAddCategoryBudget = true
                }
            } else {
                ForEach(store.categoryBudgetProgress) { prog in
                    DaylightCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: prog.category.symbolName)
                                    .foregroundStyle(prog.category.tintColor)
                                Text(prog.category.displayName)
                                    .font(.headline)
                                Spacer()
                                let pct = Int(round(prog.percentageUsed * 100))
                                DaylightBadge(
                                    prog.isOverBudget ? "\(pct)% (Over Target)" : "\(pct)% Used",
                                    icon: prog.isOverBudget ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                                    tone: prog.isOverBudget ? .overBudget : (prog.percentageUsed > 0.8 ? .warning : .positive)
                                )
                            }

                            ProgressView(value: min(1.0, max(0.0, prog.percentageUsed)))
                                .tint(prog.isOverBudget ? DaylightTheme.cautionRed : (prog.percentageUsed > 0.8 ? DaylightTheme.warning : DaylightTheme.positive))

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Spent: \(AustralianMoneyFormatter.format(cents: prog.netSpentCents)) of \(AustralianMoneyFormatter.format(cents: prog.budgetedCents))")
                                        .font(.subheadline.weight(.medium))
                                        .monospacedDigit()
                                    Text("Expected end-of-period: \(AustralianMoneyFormatter.format(cents: prog.projectedEndOfPeriodCents))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(prog.remainingCents >= 0 ? "\(AustralianMoneyFormatter.format(cents: prog.remainingCents)) left" : "\(AustralianMoneyFormatter.format(cents: abs(prog.remainingCents))) over")
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(prog.remainingCents >= 0 ? DaylightTheme.positive : DaylightTheme.cautionRed)

                                    HStack(spacing: 8) {
                                        Button("Edit Limit") {
                                            newBudgetCategory = prog.category
                                            newBudgetDollars = String(format: "%.2f", Double(prog.budgetedCents) / 100.0)
                                            if let existing = store.categoryBudgets.first(where: { $0.category == prog.category }) {
                                                newBudgetRollover = existing.rolloverEnabled
                                            }
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
                    subtitle: "Subtracted before calculating flexible spending (never double-counted when paid)",
                    trailingTitle: "+ Add Fixed Bill"
                ) {
                    showingAddCommitment = true
                }

                ForEach(store.fixedCommitments) { item in
                    HStack {
                        Image(systemName: item.category.symbolName)
                            .foregroundStyle(item.category.tintColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            Text("\(item.category.displayName) • \(item.frequency.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AustralianMoneyFormatter.format(cents: item.amountCents))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Button(role: .destructive) {
                            store.deleteFixedCommitment(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var addCategoryBudgetSheet: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Category")
                    Spacer()
                    Menu {
                        ForEach(AustralianCategory.expenseCategories) { cat in
                            Button {
                                newBudgetCategory = cat
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
                TextField("Period Limit in AUD (e.g. 380.00)", text: $newBudgetDollars)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Toggle("Enable Unspent Rollover to Next Period", isOn: $newBudgetRollover)
            }
            .navigationTitle("Set Category Limit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddCategoryBudget = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let cents = AustralianMoneyFormatter.parseToCents(newBudgetDollars), cents > 0 {
                            store.upsertCategoryBudget(category: newBudgetCategory, limitCents: cents, rolloverEnabled: newBudgetRollover)
                            showingAddCategoryBudget = false
                        }
                    }
                }
            }
        }
    }

    private var addFixedCommitmentSheet: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("Add Fixed Commitment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddCommitment = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let cents = AustralianMoneyFormatter.parseToCents(newCommitmentDollars),
                           cents > 0,
                           !newCommitmentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addFixedCommitment(
                                title: newCommitmentTitle,
                                category: newCommitmentCategory,
                                amountCents: cents,
                                frequency: newCommitmentFrequency,
                                nextDueDate: newCommitmentDueDate
                            )
                            showingAddCommitment = false
                        }
                    }
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
                        Text("Daylight detects recurring bills from your transaction history (BPAY, Direct Debit, Osko, and card subscriptions). Note: Confirming or dismissing a bill updates your budget forecast; to cancel a direct debit or subscription, contact the merchant or your bank directly.")
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
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Bills & Subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
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
                }
                .navigationTitle("Add Scheduled Bill")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddBillSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let cents = AustralianMoneyFormatter.parseToCents(billAmountDollars),
                               cents > 0,
                               !billMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    }
                }
            }
        }
    }

    private func billRow(_ bill: RecurringPaymentPrediction, isConfirmedSection: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bill.category.symbolName)
                .foregroundStyle(bill.category.tintColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(bill.category.tintColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bill.merchantName)
                        .font(.subheadline.weight(.semibold))
                    DaylightBadge(
                        bill.confidence.displayName,
                        icon: bill.isConfirmedByUser ? "checkmark.seal.fill" : "waveform.path.ecg",
                        tone: bill.isConfirmedByUser ? .positive : .neutral
                    )
                }

                Text("Next expected: \(AustralianDateHelper.formatMediumDate(bill.nextExpectedDate, timeZoneId: store.profile.timeZoneId)) • \(bill.frequency.displayName) • \(bill.paymentRail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Last payment: \(AustralianDateHelper.formatShortDate(bill.lastPaymentDate, timeZoneId: store.profile.timeZoneId)) • Linked evidence: \(max(1, bill.linkedTransactionIds.count)) txn(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !isConfirmedSection {
                    HStack(spacing: 10) {
                        Button("Confirm Schedule") {
                            store.confirmRecurringPrediction(id: bill.id)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(DaylightTheme.positive)

                        Button("Dismiss Suggestion", role: .destructive) {
                            store.dismissRecurringPrediction(id: bill.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(AustralianMoneyFormatter.format(cents: bill.expectedAmountCents))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()

                if isConfirmedSection {
                    Button("Remove", role: .destructive) {
                        store.dismissRecurringPrediction(id: bill.id)
                    }
                    .font(.caption2)
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
    @State private var newGoalInitialDollars = "500.00"
    @State private var newGoalTargetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

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
                        Text("Savings goals track your recorded progress and calculate required per-payday contributions. Goal balances do not imply funds are held in a separate custodial account unless verified in your bank account, and no investment returns are promised.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.savingsGoals.isEmpty {
                    DaylightEmptyState(
                        icon: "target",
                        title: "Create your first Australian savings goal",
                        message: "Track an Emergency Fund, Holiday, Car, or First Home Deposit with clear payday contribution targets.",
                        actionTitle: "Create Savings Goal"
                    ) {
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
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Savings Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
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
            ? min(1.0, Double(goal.currentSavedCents) / Double(goal.targetAmountCents))
            : 1.0
        let remainingCents = max(0, goal.targetAmountCents - goal.currentSavedCents)

        // Calculate suggested contribution per pay cycle if targetDate is set
        let suggestedPerCycleCents: MoneyCents? = {
            guard let targetDate = goal.targetDate, remainingCents > 0 else { return nil }
            let daysLeft = max(1, Int(targetDate.timeIntervalSince(store.referenceDate) / 86400))
            let cyclesLeft = max(1, daysLeft / max(1, store.profile.payFrequency.nominalPeriodDays))
            return remainingCents / Int64(cyclesLeft)
        }()

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
                            .font(.headline)
                        if let targetDate = goal.targetDate {
                            Text("Target date: \(AustralianDateHelper.formatMediumDate(targetDate, timeZoneId: store.profile.timeZoneId))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        editGoalName = goal.name
                        editGoalIcon = goal.iconName
                        editGoalTargetDollars = String(format: "%.2f", Double(goal.targetAmountCents) / 100.0)
                        editGoalTargetDate = goal.targetDate ?? Date()
                        selectedGoalForEdit = goal
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        contributionLinkedTransactionId = nil
                        selectedGoalForContribution = goal
                    } label: {
                        Label("Log Contribution", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)
                }

                ProgressView(value: ratio)
                    .tint(DaylightTheme.positive)

                HStack {
                    Text("Saved: \(AustralianMoneyFormatter.format(cents: goal.currentSavedCents)) (\(Int(round(ratio * 100)))%)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text("Target: \(AustralianMoneyFormatter.format(cents: goal.targetAmountCents))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let suggested = suggestedPerCycleCents {
                    Text("Suggested schedule: \(AustralianMoneyFormatter.format(cents: suggested)) per \(store.profile.payFrequency.displayName) to reach target on time.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DaylightTheme.accent)
                }

                HStack {
                    Text("Assumptions: \(goal.assumptionsNote)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteSavingsGoal(id: goal.id)
                    } label: {
                        Label("Delete Goal", systemImage: "trash")
                            .font(.caption2)
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
            }
            .navigationTitle("New Savings Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddGoal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let target = AustralianMoneyFormatter.parseToCents(newGoalTargetDollars),
                           target > 0,
                           !newGoalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let initial = AustralianMoneyFormatter.parseToCents(newGoalInitialDollars) ?? 0
                            store.addSavingsGoal(
                                name: newGoalName,
                                iconName: newGoalIcon,
                                targetAmountCents: target,
                                initialSavedCents: initial,
                                targetDate: newGoalTargetDate,
                                linkedAccountId: store.accounts.first(where: { $0.accountType == .highInterestSavings })?.id
                            )
                            showingAddGoal = false
                        }
                    }
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
            }
            .navigationTitle("Edit Savings Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedGoalForEdit = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let target = AustralianMoneyFormatter.parseToCents(editGoalTargetDollars),
                           target > 0,
                           !editGoalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.updateSavingsGoal(
                                goalId: goal.id,
                                name: editGoalName,
                                iconName: editGoalIcon,
                                targetAmountCents: target,
                                targetDate: editGoalTargetDate
                            )
                            selectedGoalForEdit = nil
                        }
                    }
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
                }
            }
            .navigationTitle("Log Contribution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedGoalForContribution = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let cents = AustralianMoneyFormatter.parseToCents(contributionDollars), cents > 0 {
                            store.addSavingsContribution(
                                goalId: goal.id,
                                amountCents: cents,
                                note: contributionNote,
                                linkedTransactionId: contributionLinkedTransactionId
                            )
                            selectedGoalForContribution = nil
                        }
                    }
                }
            }
        }
    }
}
