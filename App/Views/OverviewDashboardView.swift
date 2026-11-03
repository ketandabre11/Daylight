import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

public struct OverviewDashboardView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var greetingCoordinator: TimeBasedGreetingCoordinator
    @Binding private var isNavigationBarCompact: Bool

    @State private var showingQuickAddTransaction = false
    @State private var showingRegulatoryDisclaimer = false
    @State private var showingAccountBalances = false
    @State private var selectedTransactionForDetail: TransactionRecord? = nil
    @State private var isAmountsHidden = false
    public init(
        store: DaylightStore,
        greetingCoordinator: TimeBasedGreetingCoordinator? = nil,
        isNavigationBarCompact: Binding<Bool> = .constant(false)
    ) {
        self.store = store
        self._greetingCoordinator = StateObject(wrappedValue: greetingCoordinator ?? TimeBasedGreetingCoordinator())
        self._isNavigationBarCompact = isNavigationBarCompact
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
        VStack(spacing: 0) {
            dashboardTopBar

            ScrollView {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                        if store.isDemoMode {
                            demoModeBanner
                        }
                        if let bannerMsg = store.statusBannerMessage {
                            statusNotificationBanner(bannerMsg)
                        }
                        if !store.unclassifiedTransactions.isEmpty {
                            unclassifiedReviewBanner
                        }
                        if store.transactions.isEmpty {
                            newUserGettingStartedCard
                        }

                        // 1. Safe-to-Spend — the primary visual focus
                        heroSafeToSpendCard

                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: DaylightTheme.Spacing.lg) {
                        VStack(spacing: DaylightTheme.Spacing.lg) {
                            // 2. Spending and budget progress — concise supporting summaries
                            currentBudgetSummaryCard
                            // 3. Upcoming bills and fixed commitments — only items requiring attention
                            upcomingBillsCard
                            // 5. Savings progress — a compact summary
                            savingsSnapshotCard
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: DaylightTheme.Spacing.lg) {
                            // 4. Recent transactions — a short preview with an option to view all
                            recentTransactionsCard
                            // Secondary info: Account balances (progressive disclosure)
                            accountBalancesCollapsibleSection
                            if !store.activeInsights.isEmpty {
                                featuredInsightCard
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // 2. Spending and budget progress — concise supporting summaries
                    currentBudgetSummaryCard
                    // 3. Upcoming bills and fixed commitments — only items requiring attention
                    upcomingBillsCard
                    // 4. Recent transactions — a short preview with an option to view all
                    recentTransactionsCard
                    // 5. Savings progress — a compact summary
                    savingsSnapshotCard
                    // Secondary info: Account balances (progressive disclosure)
                    accountBalancesCollapsibleSection
                    if !store.activeInsights.isEmpty {
                        featuredInsightCard
                    }
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
            .reportsDaylightScrollPosition()
        }
        .background(DaylightAtmosphericBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingQuickAddTransaction) {
            ManualTransactionSheet(store: store)
        }
        .sheet(item: $selectedTransactionForDetail) { tx in
            TransactionDetailSheet(store: store, transaction: tx)
        }
        .onAppear {
            isNavigationBarCompact = false
            greetingCoordinator.handleAppForeground()
        }
        .onDisappear {
            greetingCoordinator.handleAppBackground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                greetingCoordinator.handleAppForeground()
            } else {
                greetingCoordinator.handleAppBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            greetingCoordinator.handleSystemTimeOrTimezoneChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            greetingCoordinator.handleSystemTimeOrTimezoneChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            greetingCoordinator.handleSystemTimeOrTimezoneChange()
        }
    }

    private var timeGreeting: String {
        greetingCoordinator.greeting
    }

    private var greetingTitle: String {
        greetingCoordinator.fullGreeting(for: store.greetingName)
    }

    // MARK: - Dashboard Top Bar (Avatar, Greeting & Actions)

    private var dashboardTopBar: some View {
        HStack(alignment: .center, spacing: isNavigationBarCompact ? 8 : 12) {
            // Profile Avatar + Personalised Greeting
            Button {
                store.selectedSection = .settings
            } label: {
                HStack(alignment: .center, spacing: isNavigationBarCompact ? 8 : 10) {
                    DaylightAvatarView(
                        avatarImageData: store.profile.avatarImageData,
                        name: store.greetingName,
                        size: isNavigationBarCompact ? 32 : 38,
                        isDemo: store.isDemoMode,
                        showBorder: true,
                        borderColor: DaylightTheme.Lime.primary
                    )

                    VStack(alignment: .leading, spacing: isNavigationBarCompact ? 0 : 2) {
                        Text(timeGreeting.uppercased())
                            .font(.system(
                                size: isNavigationBarCompact ? 8 : 10,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(DaylightTheme.Lime.mint)
                            .tracking(isNavigationBarCompact ? 0.6 : 0.8)

                        Text(store.greetingName)
                            .font(.system(
                                isNavigationBarCompact ? .headline : .title3,
                                design: .rounded,
                                weight: .bold
                            ))
                            .foregroundStyle(DaylightTheme.GlassText.primary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(greetingTitle), Profile & Settings")

            Spacer(minLength: 8)

            // Trailing glass actions (Notifications + Add Transaction)
            HStack(spacing: 8) {
                DaylightGlassIconButton(
                    icon: store.unreadNotificationCount > 0 ? "bell.badge.fill" : "bell",
                    badgeCount: store.unreadNotificationCount
                ) {
                    store.showingNotificationsSheet = true
                }
                .accessibilityLabel("Notifications (\(store.unreadNotificationCount) unread)")
                .scaleEffect(isNavigationBarCompact ? 0.84 : 1)

                DaylightGlassIconButton(icon: "plus") {
                    showingQuickAddTransaction = true
                }
                .accessibilityLabel("Add Transaction")
                .scaleEffect(isNavigationBarCompact ? 0.84 : 1)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.22),
                value: isNavigationBarCompact
            )
        }
        .padding(.horizontal, DaylightTheme.Spacing.md)
        .padding(.top, isNavigationBarCompact ? 3 : 6)
        .padding(.bottom, isNavigationBarCompact ? 3 : 6)
        .accessibilityValue(isNavigationBarCompact ? "Compact" : "Expanded")
    }

    // MARK: - Demo Mode Banner

    private var demoModeBanner: some View {
        DaylightCard(padding: DaylightTheme.Spacing.sm) {
            HStack(spacing: DaylightTheme.Spacing.sm) {
                DaylightBadge(
                    "Synthetic Demo Mode",
                    icon: "sparkles",
                    tone: .demo
                )

                Text("Viewing realistic synthetic AUD records (Sydney). Demo data is never mixed with your personal financial records.")
                    .font(DaylightTypography.caption)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    .lineLimit(2)

                Spacer()

                Button("Reset Demo") {
                    store.resetSyntheticDemoData()
                }
                .font(DaylightTypography.captionMedium)
                .buttonStyle(.bordered)
            }
        }
    }

    private func statusNotificationBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DaylightTheme.positive)
            Text(text)
                .font(DaylightTypography.callout.weight(.medium))
            Spacer()
            Button("Dismiss") {
                store.statusBannerMessage = nil
            }
            .font(DaylightTypography.captionMedium)
        }
        .padding(DaylightTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                .fill(DaylightTheme.positiveSurface(for: colorScheme))
        )
    }

    // MARK: - Hero Card: "How much can I comfortably spend today?"

    private var heroSafeToSpendCard: some View {
        VStack(spacing: DaylightTheme.Spacing.md) {
            DaylightBalanceCard(
                safeToSpendCents: summary.todaysRemainingAllowanceCents,
                availableBalanceCents: summary.everydayAvailableBankBalanceCents,
                spentTodayCents: summary.flexibleSpentTodayCents,
                nextPayDate: store.profile.nextPayDate,
                daysUntilNextPay: FinancialCalculationEngine.daysUntilNextPayDate(
                    referenceDate: store.referenceDate,
                    profile: store.profile
                ),
                isOverDailyAllowance: isOverDailyAllowance,
                ringProgress: ringProgress,
                timeZoneId: store.profile.timeZoneId,
                isAmountsHidden: $isAmountsHidden,
                onInfoTapped: {
                    store.showingCalculationExplainer = true
                }
            )

            // Helpful setup prompt when a personal workspace has not yet configured income or a flexible budget
            if !store.isDemoMode && summary.periodTakeHomeIncomeCents == 0 && summary.totalFlexibleBudgetForPeriodCents == 0 {
                HStack(alignment: .center, spacing: DaylightTheme.Spacing.sm) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(DaylightTheme.Lime.primary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set up your pay cycle to calculate your daily Safe-to-Spend")
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.GlassText.primary)
                        Text("Enter your typical take-home pay or record an income transaction — we never pre-fill synthetic budget amounts in your personal workspace.")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.GlassText.secondary)
                    }
                    Spacer()
                    Button("Configure Pay Cycle") {
                        store.showingOnboardingSheet = true
                    }
                    .font(DaylightTypography.captionMedium)
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.Lime.primary)
                }
                .padding(DaylightTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                        .fill(DaylightTheme.Glass.translucent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                        .stroke(DaylightTheme.Glass.border, lineWidth: 1)
                )
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
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.GlassText.primary)
                        Text("Daylight automatically spreads this across the remaining \(max(1, summary.remainingDaysInPeriod - 1)) days of your period, or you can adjust your budget target.")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.GlassText.secondary)
                    }
                }
                .padding(DaylightTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                        .fill(DaylightTheme.warningSurface(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                        .stroke(DaylightTheme.warning.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Bank Balances (Progressive Disclosure)

    private var accountBalancesCollapsibleSection: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            DisclosureGroup(isExpanded: $showingAccountBalances) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.vertical, 4)

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 180), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        balanceStatTile(
                            title: "Everyday Account",
                            amountCents: summary.everydayAvailableBankBalanceCents,
                            caption: "Available in primary bank account",
                            icon: "building.columns.fill",
                            tint: DaylightTheme.accent
                        )
                        balanceStatTile(
                            title: "Cash After Unpaid Bills",
                            amountCents: summary.availableCashAfterCommitmentsCents,
                            caption: "Everyday balance less \(AustralianMoneyFormatter.format(cents: summary.unpaidFixedCommitmentsRemainingCents)) unpaid commitments",
                            icon: "checkmark.shield.fill",
                            tint: DaylightTheme.positive
                        )
                        balanceStatTile(
                            title: "Total Liquid Cash",
                            amountCents: store.accounts
                                .filter { $0.connectionStatus != .disconnected && $0.accountType.isAssetAccount }
                                .reduce(MoneyCents(0)) { $0 + $1.availableBalanceCents },
                            caption: "Across all linked asset accounts",
                            icon: "banknote.fill",
                            tint: .teal
                        )
                        balanceStatTile(
                            title: "Credit & Debt",
                            amountCents: -summary.totalCreditCardAndDebtBalanceCents,
                            caption: "Total liability balance",
                            icon: "creditcard.fill",
                            tint: .orange
                        )
                    }

                    Button {
                        store.selectedSection = .accounts
                    } label: {
                        HStack {
                            Text("Manage Linked Accounts")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(DaylightTheme.forestGreen)
                        .padding(.top, 4)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .foregroundStyle(DaylightTheme.accent)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bank & Liquid Balances")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Everyday: \(AustralianMoneyFormatter.format(cents: summary.everydayAvailableBankBalanceCents)) • Cash After Bills: \(AustralianMoneyFormatter.format(cents: summary.availableCashAfterCommitmentsCents))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
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
        DaylightCard(padding: DaylightTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(DaylightTypography.captionMedium)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    Spacer()
                }
                Text(AustralianMoneyFormatter.format(cents: amountCents))
                    .font(DaylightTypography.financialAmount(size: 20, weight: .bold))
                Text(caption)
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Unclassified / Uncertain Transactions Review Banner

    private var unclassifiedReviewBanner: some View {
        DaylightCard(padding: DaylightTheme.Spacing.sm) {
            HStack(spacing: DaylightTheme.Spacing.sm) {
                Image(systemName: "questionmark.folder.fill")
                    .font(.title3)
                    .foregroundStyle(DaylightTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.unclassifiedTransactions.count) Transaction\(store.unclassifiedTransactions.count == 1 ? "" : "s") Need Classification Review")
                        .font(DaylightTypography.subheadlineMedium)
                    Text("Ambiguous merchant descriptions are never guessed automatically. Review and assign a category or merchant rule.")
                        .font(DaylightTypography.caption)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                }
                Spacer()
                Button("Review Now") {
                    store.transactionCategoryDrilldown = .cashAndUnclassified
                    store.selectedSection = .transactions
                }
                .font(DaylightTypography.captionMedium)
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
            }
        }
    }

    // MARK: - Featured Insight Card

    @ViewBuilder
    private var featuredInsightCard: some View {
        if let topInsight = store.activeInsights.first {
            DaylightInsightCard(insight: topInsight) {
                store.selectedSection = .insights
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
                                Text("\(AustralianMoneyFormatter.format(cents: prog.netSpentCents)) / \(AustralianMoneyFormatter.format(cents: prog.budgetedCents)) • \(prog.sourcePeriodType.displayName)")
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
                    ForEach(store.transactions.prefix(3)) { tx in
                        DaylightTransactionRow(
                            transaction: tx,
                            timeZoneId: store.profile.timeZoneId,
                            isAmountsHidden: isAmountsHidden
                        ) {
                            selectedTransactionForDetail = tx
                        }
                    }
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
        HStack {
            Spacer()
            Button {
                showingRegulatoryDisclaimer = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34, alignment: .center)
                    .background(
                        Circle()
                            .fill(DaylightTheme.surface(for: colorScheme))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(DaylightTheme.border(for: colorScheme), lineWidth: 1)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Regulatory disclaimer")
            .sheet(isPresented: $showingRegulatoryDisclaimer) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(DaylightTheme.accent)
                                Text("Important Information")
                                    .font(.headline)
                            }

                            Text(BrandConfig.regulatoryDisclaimer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(20)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingRegulatoryDisclaimer = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(260), .medium])
                .presentationDragIndicator(.visible)
            }
            Spacer()
        }
        .padding(.top, 4)
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
// MARK: - Dashboard Profile Management Sheet

public struct DashboardProfileSheet: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var preferredNameDraft: String = ""
    @State private var avatarImageDataDraft: Data? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPresetId: String? = nil
    @State private var isProcessingPhoto: Bool = false
    @State private var statusFeedback: String? = nil
    @State private var errorMessage: String? = nil

    public init(store: DaylightStore) {
        self.store = store
        _preferredNameDraft = State(initialValue: store.profile.preferredName)
        _avatarImageDataDraft = State(initialValue: store.profile.avatarImageData)
    }

    private var effectiveName: String {
        let trimmed = preferredNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? store.greetingName : trimmed
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DaylightTheme.Spacing.lg) {
                    // 1. Avatar Preview Header
                    avatarPreviewHeader

                    // 2. Greeting Name Editor
                    nameEditorCard

                    // 3. Photo & Preset Avatar Options (Personal Workspace only)
                    if !store.isDemoMode {
                        photoPickerCard
                        presetAvatarsCard

                        if avatarImageDataDraft != nil {
                            removePhotoButton
                        }
                    } else {
                        demoWorkspaceCard
                    }

                    // 4. Quick Settings Link
                    fullSettingsCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DaylightTheme.cautionRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(DaylightTheme.Spacing.md)
            }
            .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Profile & Greeting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Avatar Preview Header

    private var avatarPreviewHeader: some View {
        VStack(spacing: DaylightTheme.Spacing.sm) {
            DaylightAvatarView(
                avatarImageData: avatarImageDataDraft,
                name: effectiveName,
                size: 96,
                isDemo: store.isDemoMode,
                showBorder: true,
                borderColor: DaylightTheme.accent
            )

            Text("G'day, \(effectiveName)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

            if let statusFeedback {
                Text(statusFeedback)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DaylightTheme.positive)
                    .transition(.opacity)
            } else {
                Text(store.isDemoMode ? "Synthetic Australian Demo Avatar" : "Visible across your dashboard and daily summaries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Name Editor Card

    private var nameEditorCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Greeting Name", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                TextField("Your preferred name (e.g. Ketan)", text: $preferredNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                HStack {
                    Text("Dashboard preview:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("G'day, \(effectiveName)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DaylightTheme.accent)
                }
            }
        }
    }

    // MARK: - Photo Picker Card

    private var photoPickerCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Custom Photo", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text(avatarImageDataDraft == nil ? "Choose Photo from Library" : "Change Photo")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if isProcessingPhoto {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                            .fill(DaylightTheme.accent)
                    )
                    .foregroundStyle(.white)
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    isProcessingPhoto = true
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let optimized = ProfileImageProcessor.process(data: data) {
                            await MainActor.run {
                                withAnimation(.spring(duration: 0.25)) {
                                    self.avatarImageDataDraft = optimized
                                    self.selectedPresetId = nil
                                    self.statusFeedback = "Photo selected from library."
                                    self.isProcessingPhoto = false
                                }
                            }
                        } else {
                            await MainActor.run {
                                self.isProcessingPhoto = false
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preset Avatars Card

    private var presetAvatarsCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Or Choose an Australian Preset", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PresetAvatar.australianPresets) { preset in
                        Button {
                            selectPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [preset.startColor, preset.endColor],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)

                                    Image(systemName: preset.systemName)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)

                                    if selectedPresetId == preset.id {
                                        Circle()
                                            .strokeBorder(DaylightTheme.accent, lineWidth: 2.5)
                                            .frame(width: 52, height: 52)

                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white, DaylightTheme.positive)
                                            .offset(x: 18, y: -18)
                                    }
                                }

                                Text(preset.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                                    .fill(selectedPresetId == preset.id ? DaylightTheme.accent.opacity(0.10) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Remove Photo Button

    private var removePhotoButton: some View {
        Button(role: .destructive) {
            withAnimation(.spring(duration: 0.25)) {
                avatarImageDataDraft = nil
                selectedPresetId = nil
                statusFeedback = "Reverted to initials avatar."
            }
        } label: {
            Label("Remove Photo & Use Initials", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DaylightTheme.cautionRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(DaylightTheme.cautionRed)
    }

    // MARK: - Demo Workspace Card

    private var demoWorkspaceCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                DaylightBadge("Synthetic Demo Mode", icon: "sparkles", tone: .demo)
                Text("You are currently exploring in Synthetic Demo Mode. Profile photos and personal preferences are preserved in your personal workspace when you switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Full Settings Link

    private var fullSettingsCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looking for more preferences?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                        Text("Pay cycle, savings targets, notifications, and export options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        store.selectedSection = .settings
                        dismiss()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectPreset(_ preset: PresetAvatar) {
        selectedPresetId = preset.id
        if let data = ProfileImageProcessor.renderPresetAvatar(preset) {
            withAnimation(.spring(duration: 0.25)) {
                self.avatarImageDataDraft = data
                self.statusFeedback = "Selected \(preset.title)."
            }
        }
    }

    private func saveProfile() {
        do {
            // 1. Update avatar
            try store.updateProfileAvatar(imageData: avatarImageDataDraft)

            // 2. Update preferred name
            var p = store.profile
            let cleanName = preferredNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty {
                p.preferredName = cleanName
            }
            p.tenantId = store.activeTenantId
            try store.updateProfile(p)

            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
