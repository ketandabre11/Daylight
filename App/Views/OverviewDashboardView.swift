import SwiftUI

public struct OverviewDashboardView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickAddTransaction = false
    @State private var selectedTransactionForDetail: TransactionRecord? = nil

    public init(store: DaylightStore) {
        self.store = store
    }

    private var summary: DailyAllowanceSummary {
        store.allowanceSummary
    }

    private var isOverDailyAllowance: Bool {
        summary.todaysRemainingAllowanceCents < 0
    }

    private var ringProgress: Double {
        guard summary.todaysStartingAllowanceCents > 0 else {
            return summary.flexibleSpentTodayCents > 0 ? 1.0 : 0.0
        }
        return Double(summary.flexibleSpentTodayCents) / Double(summary.todaysStartingAllowanceCents)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                workspaceModeBanner
                if let bannerMsg = store.statusBannerMessage {
                    statusNotificationBanner(bannerMsg)
                }
                if store.transactions.isEmpty {
                    newUserGettingStartedCard
                }
                heroSafeToSpendCard
                balancesVsBudgetComparisonGrid
                quickActionsRow
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: DaylightTheme.Spacing.lg) {
                        VStack(spacing: DaylightTheme.Spacing.lg) {
                            currentBudgetSummaryCard
                            upcomingBillsCard
                            savingsSnapshotCard
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: DaylightTheme.Spacing.lg) {
                            featuredInsightCard
                            recentTransactionsCard
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    currentBudgetSummaryCard
                    featuredInsightCard
                    upcomingBillsCard
                    recentTransactionsCard
                    savingsSnapshotCard
                }
                regulatoryFooter
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            store.refreshWorkspaceCategories()
            store.recalculateDerivedState()
        }
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle(greetingTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showingNotificationsSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: store.unreadNotificationCount > 0 ? "bell.badge.fill" : "bell")
                        if store.unreadNotificationCount > 0 {
                            Text("\(store.unreadNotificationCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DaylightTheme.cautionRed))
                                .offset(x: 8, y: -6)
                        }
                    }
                }
                .accessibilityLabel("Notifications (\(store.unreadNotificationCount) unread)")

                Button {
                    showingQuickAddTransaction = true
                } label: {
                    Label("Add Transaction", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $store.showingCalculationExplainer) {
            CalculationExplainerSheet(store: store)
        }
        .sheet(isPresented: $showingQuickAddTransaction) {
            ManualTransactionSheet(store: store)
        }
        .sheet(item: $selectedTransactionForDetail) { tx in
            TransactionDetailSheet(store: store, transaction: tx)
        }
    }

    private var greetingTitle: String {
        let name = store.profile.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? BrandConfig.appName : "G'day, \(name)"
    }

    // MARK: - Demo vs Personal Workspace Banner

    private var workspaceModeBanner: some View {
        DaylightCard(padding: 12) {
            HStack(spacing: 12) {
                DaylightBadge(
                    store.isDemoMode ? "Synthetic Australian Demo Mode" : "Personal Workspace (Isolated)",
                    icon: store.isDemoMode ? "sparkles" : "lock.shield.fill",
                    tone: store.isDemoMode ? .demo : .positive
                )

                Text(
                    store.isDemoMode
                        ? "Viewing realistic synthetic AUD records (Sydney). Demo data is never mixed with your personal financial records."
                        : "Viewing your isolated personal workspace (\(store.profile.timeZoneId))."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

                Spacer()

                if store.isDemoMode {
                    Button("Reset Demo") {
                        store.resetSyntheticDemoData()
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                }

                Button(store.isDemoMode ? "Switch to Personal" : "Switch to Demo") {
                    store.switchWorkspaceMode(toDemo: !store.isDemoMode)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
            }
        }
    }

    private func statusNotificationBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DaylightTheme.positive)
            Text(text)
                .font(.footnote.weight(.medium))
            Spacer()
            Button("Dismiss") {
                store.statusBannerMessage = nil
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .fill(DaylightTheme.positive.opacity(0.12))
        )
    }

    // MARK: - Hero Card: "How much can I comfortably spend today?"

    private var heroSafeToSpendCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOW MUCH CAN I COMFORTABLY SPEND TODAY?")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DaylightTheme.accent)
                            .tracking(0.5)

                        Text("Safe-to-Spend Today")
                            .font(.title2.weight(.semibold))

                        Text("Period: \(AustralianDateHelper.formatShortDate(summary.periodStart, timeZoneId: store.profile.timeZoneId)) – \(AustralianDateHelper.formatShortDate(summary.periodEnd, timeZoneId: store.profile.timeZoneId)) • \(summary.remainingDaysInPeriod) day\(summary.remainingDaysInPeriod == 1 ? "" : "s") left until next payday")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        store.showingCalculationExplainer = true
                    } label: {
                        Label("How this is calculated", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DaylightTheme.Spacing.xl) {
                        AllowanceRingView(
                            progress: ringProgress,
                            isOverAllowance: isOverDailyAllowance,
                            centerTitle: isOverDailyAllowance ? "Over Today's Target" : "Remaining Today",
                            centerAmount: AustralianMoneyFormatter.format(cents: summary.todaysRemainingAllowanceCents),
                            subtitle: isOverDailyAllowance ? "Adjusted tomorrow" : "Safe to spend"
                        )
                        heroBreakdownMetrics
                    }

                    VStack(spacing: DaylightTheme.Spacing.md) {
                        AllowanceRingView(
                            progress: ringProgress,
                            isOverAllowance: isOverDailyAllowance,
                            centerTitle: isOverDailyAllowance ? "Over Today's Target" : "Remaining Today",
                            centerAmount: AustralianMoneyFormatter.format(cents: summary.todaysRemainingAllowanceCents),
                            subtitle: isOverDailyAllowance ? "Adjusted tomorrow" : "Safe to spend"
                        )
                        heroBreakdownMetrics
                    }
                }

                // Empathetic explanation when over or under today's allowance
                if isOverDailyAllowance {
                    let overBy = abs(summary.todaysRemainingAllowanceCents)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(DaylightTheme.warning)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today's spending is \(AustralianMoneyFormatter.format(cents: overBy)) above your daily target — and that's completely okay.")
                                .font(.subheadline.weight(.semibold))
                            Text("Daylight automatically spreads this across the remaining \(max(1, summary.remainingDaysInPeriod - 1)) days of your period, or you can adjust your budget target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                            .fill(DaylightTheme.warning.opacity(0.12))
                    )
                }
            }
        }
    }

    private var heroBreakdownMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricRow(
                label: "Today's Opening Allowance",
                value: AustralianMoneyFormatter.format(cents: summary.todaysStartingAllowanceCents),
                detail: "Baseline: \(AustralianMoneyFormatter.format(cents: summary.baselineDailyAllowanceCents))/day"
            )
            Divider()
            metricRow(
                label: "Today's Eligible Flexible Spending",
                value: AustralianMoneyFormatter.format(cents: summary.flexibleSpentTodayCents),
                detail: "Excludes fixed bills & internal transfers"
            )
            Divider()
            metricRow(
                label: "Remaining Flexible Budget (Period)",
                value: AustralianMoneyFormatter.format(cents: summary.remainingFlexibleBudgetForPeriodCents),
                detail: "Of \(AustralianMoneyFormatter.format(cents: summary.totalFlexibleBudgetForPeriodCents)) total flexible pool"
            )
            Divider()
            metricRow(
                label: "Next Payday / Cycle Reset",
                value: AustralianDateHelper.formatMediumDate(store.profile.nextPayDate, timeZoneId: store.profile.timeZoneId),
                detail: "Expected \(AustralianMoneyFormatter.format(cents: store.profile.typicalTakeHomePayCents)) (\(store.profile.payFrequency.displayName))"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(label: String, value: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
    }

    // MARK: - Bank Balances vs Budgeting Figures (Explicit Distinction)

    private var balancesVsBudgetComparisonGrid: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            DaylightSectionHeader(
                title: "Account Balances vs Budget Allowance",
                subtitle: "Budget allowances are planning targets — never confused with your bank's available cash balance."
            )

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 220), spacing: DaylightTheme.Spacing.sm)
                ],
                spacing: DaylightTheme.Spacing.sm
            ) {
                balanceStatTile(
                    title: "Everyday Bank Available",
                    amountCents: summary.everydayAvailableBankBalanceCents,
                    caption: "Actual funds in Everyday Account",
                    icon: "building.columns.fill",
                    tint: DaylightTheme.accent
                )
                balanceStatTile(
                    title: "Cash After Unpaid Bills",
                    amountCents: summary.availableCashAfterCommitmentsCents,
                    caption: "Everyday balance minus \(AustralianMoneyFormatter.format(cents: summary.unpaidFixedCommitmentsRemainingCents)) unpaid bills",
                    icon: "checkmark.shield.fill",
                    tint: DaylightTheme.positive
                )
                balanceStatTile(
                    title: "Total Liquid Savings & Cash",
                    amountCents: summary.totalLiquidCashAcrossAccountsCents + (store.accounts.filter { $0.accountType == .highInterestSavings }.reduce(0) { $0 + $1.availableBalanceCents }),
                    caption: "Across all linked asset accounts",
                    icon: "banknote.fill",
                    tint: .teal
                )
                balanceStatTile(
                    title: "Credit Card & Loan Balances",
                    amountCents: -summary.totalCreditCardAndDebtBalanceCents,
                    caption: "Current posted liability balances",
                    icon: "creditcard.fill",
                    tint: .orange
                )
            }
        }
    }

    private func balanceStatTile(
        title: String,
        amountCents: MoneyCents,
        caption: String,
        icon: String,
        tint: Color
    ) -> some View {
        DaylightCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(AustralianMoneyFormatter.format(cents: amountCents))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Unclassified / Uncertain Transactions Review Banner

    private var unclassifiedReviewBanner: some View {
        DaylightCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.folder.fill")
                    .font(.title3)
                    .foregroundStyle(DaylightTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.unclassifiedTransactions.count) Transaction\(store.unclassifiedTransactions.count == 1 ? "" : "s") Need Classification Review")
                        .font(.subheadline.weight(.semibold))
                    Text("Ambiguous merchant descriptions are never guessed automatically. Review and assign a category or merchant rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Now") {
                    store.transactionCategoryDrilldown = .cashAndUnclassified
                    store.selectedSection = .transactions
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
            }
        }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    store.selectedSection = .transactions
                } label: {
                    Label("View Today's Transactions", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)

                Button {
                    store.showingStatementImporter = true
                } label: {
                    Label("Import Bank CSV Statement", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    store.selectedSection = .budgets
                } label: {
                    Label("Adjust Budget & Pay Cycle", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                Button {
                    store.selectedSection = .bills
                } label: {
                    Label("Review Upcoming Bills", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.bordered)

                Button {
                    store.showingCalculationExplainer = true
                } label: {
                    Label("Understand Spending Calculation", systemImage: "function")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Featured Insight Card

    @ViewBuilder
    private var featuredInsightCard: some View {
        if let topInsight = store.activeInsights.first {
            DaylightCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        DaylightBadge("Evidence-Backed Insight", icon: "lightbulb.fill", tone: topInsight.severity == .headsUp ? .warning : .positive)
                        Spacer()
                        Button("All Insights") {
                            store.selectedSection = .insights
                        }
                        .font(.caption.weight(.semibold))
                    }
                    Text(topInsight.title)
                        .font(.headline)
                    Text(topInsight.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(topInsight.actionableRecommendation)
                        .font(.caption)
                        .foregroundStyle(DaylightTheme.accent)
                }
            }
        }
    }

    // MARK: - Upcoming Bills Card

    private var upcomingBillsCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                DaylightSectionHeader(
                    title: "Upcoming Bills & Commitments",
                    subtitle: "Next 30 days • Confirmed vs predicted",
                    trailingTitle: "Manage Bills"
                ) {
                    store.selectedSection = .bills
                }

                if store.recurringPredictions.isEmpty {
                    Text("No upcoming recurring payments detected yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(store.recurringPredictions.prefix(4)) { bill in
                        HStack(spacing: 12) {
                            Image(systemName: bill.category.symbolName)
                                .foregroundStyle(bill.category.tintColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(bill.category.tintColor.opacity(0.14))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(bill.merchantName)
                                        .font(.subheadline.weight(.medium))
                                    if bill.isConfirmedByUser {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption2)
                                            .foregroundStyle(DaylightTheme.positive)
                                    }
                                }
                                Text("Due \(AustralianDateHelper.formatShortDate(bill.nextExpectedDate, timeZoneId: store.profile.timeZoneId)) • \(bill.frequency.displayName) • \(bill.paymentRail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(AustralianMoneyFormatter.format(cents: bill.expectedAmountCents))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - New User Empty-Workspace Action Card (4 Required Actions)

    private var newUserGettingStartedCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DaylightTheme.forestGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your personal workspace is ready")
                            .font(.headline)
                        Text("Start with real figures — no synthetic transactions have been copied into your account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
                    spacing: 10
                ) {
                    Button {
                        showingQuickAddTransaction = true
                    } label: {
                        Label("Add a transaction", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.forestGreen)

                    Button {
                        store.showingStatementImporter = true
                    } label: {
                        Label("Import a bank statement", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.selectedSection = .budgets
                    } label: {
                        Label("Set a budget", systemImage: "chart.pie.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.selectedSection = .savings
                    } label: {
                        Label("Create a savings goal", systemImage: "target")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Current Budget Summary & Progress Card

    private var currentBudgetSummaryCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                DaylightSectionHeader(
                    title: "Current Budget Summary",
                    subtitle: "Pay-cycle category budgets & spending progress",
                    trailingTitle: "Manage Budgets"
                ) {
                    store.selectedSection = .budgets
                }

                if store.categoryBudgetProgress.isEmpty {
                    HStack {
                        Text("No category budgets set yet for this pay cycle.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Set a budget") {
                            store.selectedSection = .budgets
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(store.categoryBudgetProgress.prefix(4)) { prog in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(prog.category.displayName, systemImage: prog.category.symbolName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(AustralianMoneyFormatter.format(cents: prog.netSpentCents)) / \(AustralianMoneyFormatter.format(cents: prog.budgetedCents))")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(prog.isOverBudget ? DaylightTheme.cautionRed : .primary)
                            }
                            ProgressView(value: min(max(prog.percentageUsed, 0), 1.0))
                                .tint(prog.isOverBudget ? DaylightTheme.cautionRed : (prog.percentageUsed > 0.8 ? DaylightTheme.warning : DaylightTheme.forestGreen))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Recent Transactions Card

    private var recentTransactionsCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                DaylightSectionHeader(
                    title: "Recent Transactions",
                    subtitle: "Tap any transaction to edit category, split, or inspect source",
                    trailingTitle: "View All Transactions"
                ) {
                    store.selectedSection = .transactions
                }

                if store.transactions.isEmpty {
                    DaylightEmptyState(
                        icon: "list.bullet.rectangle.portrait",
                        title: "Your money activity will appear here",
                        message: "Add a transaction manually or import an Australian bank CSV statement to begin tracking.",
                        actionTitle: "Add a transaction"
                    ) {
                        showingQuickAddTransaction = true
                    }
                } else {
                    ForEach(store.transactions.prefix(6)) { tx in
                        Button {
                            selectedTransactionForDetail = tx
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tx.category.symbolName)
                                    .foregroundStyle(tx.category.tintColor)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(tx.category.tintColor.opacity(0.14)))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(tx.merchantName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if tx.status == .pending {
                                            Text("Pending")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                                .foregroundStyle(.orange)
                                        }
                                        if tx.classificationConfidence < 0.70 {
                                            Text("Review")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(DaylightTheme.warning.opacity(0.2)))
                                                .foregroundStyle(DaylightTheme.warning)
                                        }
                                    }
                                    Text("\(tx.category.displayName) • \(AustralianDateHelper.formatShortDate(tx.occurredAt, timeZoneId: store.profile.timeZoneId))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(
                                        AustralianMoneyFormatter.format(
                                            cents: tx.direction == .debit ? -tx.amountCents : tx.amountCents,
                                            showPlusForPositive: true
                                        )
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(tx.direction == .credit ? DaylightTheme.positive : .primary)

                                    Text(transactionKindBadgeLabel(for: tx))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        store.selectedSection = .transactions
                    } label: {
                        HStack {
                            Text("View All Transactions (\(store.transactions.count))")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(DaylightTheme.forestGreen)
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func transactionKindBadgeLabel(for tx: TransactionRecord) -> String {
        switch tx.kind {
        case .income:
            return "Income"
        case .refund, .reversal:
            return "Refund / Rebate"
        case .ownAccountTransfer, .creditCardRepayment:
            return "Transfer (Non-spend)"
        default:
            return tx.excludeFromBudget ? "Excluded from budget" : "Expense"
        }
    }

    // MARK: - Savings Goals Snapshot Card

    private var savingsSnapshotCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                DaylightSectionHeader(
                    title: "Savings Goals Progress",
                    subtitle: "Planned savings: \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents))/period",
                    trailingTitle: "Manage Goals"
                ) {
                    store.selectedSection = .savings
                }

                if store.savingsGoals.isEmpty {
                    Text("No savings goals configured yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.savingsGoals.prefix(3)) { goal in
                        let progress = goal.targetAmountCents > 0
                            ? min(1.0, Double(goal.currentSavedCents) / Double(goal.targetAmountCents))
                            : 0.0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(goal.name, systemImage: goal.iconName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(AustralianMoneyFormatter.formatWholeDollars(cents: goal.currentSavedCents)) / \(AustralianMoneyFormatter.formatWholeDollars(cents: goal.targetAmountCents))")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                            }
                            ProgressView(value: progress)
                                .tint(DaylightTheme.positive)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var regulatoryFooter: some View {
        Text(BrandConfig.regulatoryDisclaimer)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

// MARK: - Transparent Calculation Explainer Sheet

public struct CalculationExplainerSheet: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                Section("Active Budgeting Method") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.allowanceSummary.budgetingMethodUsed.displayName)
                            .font(.headline)
                        Text(store.allowanceSummary.budgetingMethodUsed.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Step-by-Step Mathematical Derivation (AUD)") {
                    ForEach(store.allowanceSummary.calculationSteps, id: \.self) { step in
                        Text(step)
                            .font(.subheadline)
                            .monospacedDigit()
                            .padding(.vertical, 2)
                    }
                }

                Section("Transaction Rules Applied Automatically") {
                    Label("Transfers between your own accounts are never counted as consumption.", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.footnote)
                    Label("Credit card purchases count when spent; credit card bill repayments are excluded so they are never double-counted.", systemImage: "creditcard.fill")
                        .font(.footnote)
                    Label("Fixed commitments already paid during the period are reconciled so the same bill is never subtracted twice.", systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                    Label("Refunds and Medicare rebates reduce net spending in their category rather than inflating income.", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.footnote)
                }
            }
            .navigationTitle("Spending Allowance Formula")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
