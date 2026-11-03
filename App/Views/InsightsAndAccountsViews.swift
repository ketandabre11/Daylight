import SwiftUI
import Charts

// MARK: - Screen G: Insights & Analytics View

public struct InsightsAnalyticsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: DaylightStore) {
        self.store = store
    }

    private struct CategorySpendPoint: Identifiable {
        var id: String { category.rawValue }
        let category: AustralianCategory
        let netCents: MoneyCents
        var dollars: Double { Double(netCents) / 100.0 }
    }

    private struct DailySpendPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let label: String
        let spentCents: MoneyCents
        var dollars: Double { Double(spentCents) / 100.0 }
    }

    private struct MerchantSpendPoint: Identifiable {
        var id: String { merchant }
        let merchant: String
        let netCents: MoneyCents
        let count: Int
    }

    private var categorySpendData: [CategorySpendPoint] {
        var totals: [AustralianCategory: MoneyCents] = [:]
        for tx in store.transactions {
            for cat in AustralianCategory.expenseCategories {
                let contrib = FinancialCalculationEngine.netSpendContributionCents(
                    for: tx,
                    categoryFilter: cat,
                    includeFixedCategories: true
                )
                if contrib != 0 {
                    totals[cat, default: 0] += contrib
                }
            }
        }
        return totals
            .compactMap { cat, cents in
                cents > 0 ? CategorySpendPoint(category: cat, netCents: cents) : nil
            }
            .sorted { $0.netCents > $1.netCents }
    }

    private var last14DaysSpendData: [DailySpendPoint] {
        let cal = AustralianDateHelper.calendar(for: store.profile.timeZoneId)
        let todayStart = cal.startOfDay(for: store.referenceDate)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_AU")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "d MMM"

        return (0..<14).reversed().map { offset in
            let dayStart = cal.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let spent = store.transactions
                .filter { $0.occurredAt >= dayStart && $0.occurredAt < dayEnd }
                .reduce(MoneyCents(0)) { partial, tx in
                    partial + FinancialCalculationEngine.netSpendContributionCents(
                        for: tx,
                        includeFixedCategories: false
                    )
                }
            return DailySpendPoint(
                date: dayStart,
                label: fmt.string(from: dayStart),
                spentCents: max(0, spent)
            )
        }
    }

    private var topMerchants: [MerchantSpendPoint] {
        var map: [String: (cents: MoneyCents, count: Int)] = [:]
        for tx in store.transactions where tx.status != .reversed && !tx.excludeFromBudget && tx.direction == .debit && tx.kind != .ownAccountTransfer && tx.kind != .creditCardRepayment {
            let cur = map[tx.merchantName] ?? (0, 0)
            map[tx.merchantName] = (cur.cents + tx.amountCents, cur.count + 1)
        }
        return map.map { MerchantSpendPoint(merchant: $0.key, netCents: $0.value.cents, count: $0.value.count) }
            .sorted { $0.netCents > $1.netCents }
            .prefix(6)
            .map { $0 }
    }

    private var recurringVsDiscretionaryTuple: (recurringCents: MoneyCents, discretionaryCents: MoneyCents) {
        var rec: MoneyCents = 0
        var disc: MoneyCents = 0
        for tx in store.transactions {
            let netAll = FinancialCalculationEngine.netSpendContributionCents(for: tx, includeFixedCategories: true)
            guard netAll != 0 else { continue }
            if tx.isRecurring || tx.category.isDefaultFixedCommitment {
                rec += netAll
            } else {
                disc += netAll
            }
        }
        return (max(0, rec), max(0, disc))
    }

    private var fySummary: (label: String, incomeCents: MoneyCents, spendCents: MoneyCents) {
        let bounds = AustralianDateHelper.financialYearBounds(for: store.referenceDate, timeZoneId: store.profile.timeZoneId)
        let fyTxs = store.transactions.filter { $0.occurredAt >= bounds.start && $0.occurredAt <= bounds.end }
        let inc = fyTxs.filter { FinancialCalculationEngine.isVerifiedIncome($0) }.reduce(MoneyCents(0)) { $0 + $1.amountCents }
        let sp = fyTxs.reduce(MoneyCents(0)) { $0 + FinancialCalculationEngine.netSpendContributionCents(for: $1, includeFixedCategories: true) }
        return (bounds.label, inc, max(0, sp))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                // Milestone 2 Advanced Spending Analytics Engine
                SpendingAnalyticsDashboardView(store: store)

                // Financial Year & Income/Expenditure Overview
                incomeVsExpenditureAndFYCard

                // Additional Deterministic In-App Insights
                deterministicInsightsSection
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Insights & Analytics")
    }

    private var deterministicInsightsSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            DaylightSectionHeader(
                title: "Evidence-Backed Insights",
                subtitle: "Every insight is grounded in deterministic transaction calculations — never unverified AI guesses."
            )

            ForEach(store.activeInsights) { insight in
                let badgeIcon: String = {
                    switch insight.severity {
                    case .positive: return "checkmark.seal.fill"
                    case .headsUp: return "exclamationmark.circle.fill"
                    case .neutral: return "info.circle.fill"
                    }
                }()
                let badgeTone: FinancialBadgeTone = {
                    switch insight.severity {
                    case .positive: return .positive
                    case .headsUp: return .warning
                    case .neutral: return .neutral
                    }
                }()
                DaylightCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            DaylightBadge(
                                insight.calculationDetail,
                                icon: badgeIcon,
                                tone: badgeTone
                            )
                            Spacer()
                            if !insight.supportingTransactionIds.isEmpty {
                                Text("Backed by \(insight.supportingTransactionIds.count) txn(s)")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            }
                        }
                        Text(insight.title)
                            .font(DaylightTypography.cardTitle)
                        Text(insight.summary)
                            .font(DaylightTypography.subheadline)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Text("Suggested action: \(insight.actionableRecommendation)")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.accent)
                    }
                }
            }
        }
    }

    private var categorySpendChartCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                DaylightSectionHeader(
                    title: "Spending by Category (Tap to Drill Down)",
                    subtitle: "Excludes own-account transfers and credit card bill repayments; net of Medicare & merchant refunds"
                )

                if categorySpendData.isEmpty {
                    Text("Not enough transaction data to display category breakdown.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(categorySpendData) { item in
                        BarMark(
                            x: .value("Net Spend (AUD)", item.dollars),
                            y: .value("Category", item.category.displayName)
                        )
                        .foregroundStyle(item.category.tintColor)
                        .annotation(position: .trailing) {
                            Text(AustralianMoneyFormatter.format(cents: item.netCents))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: CGFloat(max(180, categorySpendData.count * 38)))

                    Divider()

                    Text("Tap a category below to inspect its underlying transactions:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categorySpendData) { item in
                                Button {
                                    store.transactionCategoryDrilldown = item.category
                                    store.selectedSection = .transactions
                                } label: {
                                    Label("\(item.category.displayName) (\(AustralianMoneyFormatter.formatWholeDollars(cents: item.netCents)))", systemImage: item.category.symbolName)
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dailyFlexibleSpendChartCard: some View {
        let baselineDollars = Double(store.allowanceSummary.baselineDailyAllowanceCents) / 100.0
        return DaylightCard {
            VStack(alignment: .leading, spacing: 8) {
                DaylightSectionHeader(
                    title: "Flexible Spending Over Last 14 Days vs Daily Allowance",
                    subtitle: "Dashed rule indicates your baseline daily safe-to-spend (\(AustralianMoneyFormatter.format(cents: store.allowanceSummary.baselineDailyAllowanceCents))/day)"
                )

                Chart {
                    ForEach(last14DaysSpendData) { pt in
                        BarMark(
                            x: .value("Day", pt.label),
                            y: .value("Flexible Spend (AUD)", pt.dollars)
                        )
                        .foregroundStyle(pt.dollars > baselineDollars ? DaylightTheme.warning : DaylightTheme.positive)
                    }

                    if baselineDollars > 0 {
                        RuleMark(y: .value("Baseline Daily Allowance", baselineDollars))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .foregroundStyle(DaylightTheme.accent)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var incomeVsExpenditureAndFYCard: some View {
        let fy = fySummary
        let ratio = recurringVsDiscretionaryTuple
        let totalOut = max(1, ratio.recurringCents + ratio.discretionaryCents)
        let recPct = Int(round(Double(ratio.recurringCents) / Double(totalOut) * 100))

        return DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                DaylightSectionHeader(
                    title: "AFY (\(fy.label)) & Spend Ratio",
                    subtitle: "1 July – 30 June Australian Financial Year tracking"
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 8, alignment: .top)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(fy.label) Recorded Income")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(AustralianMoneyFormatter.format(cents: fy.incomeCents))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DaylightTheme.positive)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(fy.label) Net Expenditure")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(AustralianMoneyFormatter.format(cents: fy.spendCents))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fixed & Recurring vs Discretionary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(recPct)% Fixed / \(100 - recPct)% Flexible")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DaylightTheme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                }
            }
        }
    }

    private var topMerchantsAndRecurringRatioCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 10) {
                DaylightSectionHeader(
                    title: "Top Australian Merchants by Spend",
                    subtitle: "Tap a merchant to search its transactions"
                )

                ForEach(topMerchants) { item in
                    HStack {
                        Text(item.merchant)
                            .font(DaylightTypography.bodyMedium)
                        Text("(\(item.count) txn\(item.count == 1 ? "" : "s"))")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(AustralianMoneyFormatter.format(cents: item.netCents))
                            .font(DaylightTypography.financialAmount(size: 15, weight: .bold))
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }
}

// MARK: - Screen H: Accounts & CDR Open Banking Adapter View

public struct AccountsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddAccountSheet = false
    @State private var instName = "CommBank"
    @State private var acctNickname = "Everyday Smart Access"
    @State private var acctType: FinancialAccountType = .everydayTransaction
    @State private var maskedDigits = "4109"
    @State private var openingBalanceDollars = "1850.00"

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                cdrArchitectureTransparencyCard
                accountsListSection
                consentRecordsSection
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Accounts & Connections")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showingStatementImporter = true
                } label: {
                    Label("Import CSV Statement", systemImage: "tray.and.arrow.down")
                }

                Button {
                    showingAddAccountSheet = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddAccountSheet) {
            NavigationStack {
                Form {
                    TextField("Australian Institution (e.g. CommBank, NAB, Macquarie, Up)", text: $instName)
                    TextField("Account Nickname", text: $acctNickname)
                    HStack {
                        Text("Account Type")
                        Spacer()
                        Menu {
                            ForEach(FinancialAccountType.allCases) { t in
                                Button {
                                    acctType = t
                                } label: {
                                    if t == acctType {
                                        Label(t.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(t.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(acctType.displayName, icon: acctType.symbolName)
                        }
                    }
                    TextField("Last 4 Account Digits", text: $maskedDigits)
                    TextField("Opening Balance in AUD (e.g. 1850.00)", text: $openingBalanceDollars)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                .navigationTitle("Add Manual Account")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddAccountSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add Account") {
                            if let cents = AustralianMoneyFormatter.parseToCents(openingBalanceDollars) {
                                store.addManualAccount(
                                    institutionName: instName,
                                    nickname: acctNickname,
                                    accountType: acctType,
                                    maskedDigits: maskedDigits,
                                    openingBalanceCents: acctType.isAssetAccount ? cents : -abs(cents)
                                )
                                showingAddAccountSheet = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var cdrArchitectureTransparencyCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    DaylightBadge("Open Banking / CDR Adapter Architecture", icon: "shield.lefthalf.filled", tone: .neutral)
                    Spacer()
                }
                Text("Australian Consumer Data Right (CDR) & Manual Statement Support")
                    .font(.headline)
                Text("Daylight uses a provider-agnostic Account Connection Adapter interface supporting manual accounts, Australian CSV statement imports, and CDR Open Banking consent lifecycles. Note: Live CDR data sharing requires ACCC Data Recipient accreditation or an approved CDR intermediary. This build operates in local Manual / CDR Sandbox Simulation mode and never scrapes bank credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountsListSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            DaylightSectionHeader(
                title: "Linked & Manual Accounts (\(store.accounts.count))",
                subtitle: "Available Balance vs Current Ledger Balance clearly distinguished"
            )

            if store.accounts.isEmpty {
                DaylightEmptyState(
                    icon: "building.columns",
                    title: "No accounts in this workspace yet",
                    message: "Add a manual Australian bank account or import a CSV statement to get started.",
                    actionTitle: "Add Manual Account"
                ) {
                    showingAddAccountSheet = true
                }
            } else {
                ForEach(store.accounts) { acct in
                    DaylightCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: acct.accountType.symbolName)
                                    .font(.title3)
                                    .foregroundStyle(DaylightTheme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(DaylightTheme.accent.opacity(0.12)))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(acct.nickname)
                                            .font(DaylightTypography.cardTitle)
                                        Text(acct.maskedAccountNumber)
                                            .font(DaylightTypography.caption.monospaced())
                                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                    }
                                    Text("\(acct.institutionName) • \(acct.accountType.displayName)")
                                        .font(DaylightTypography.caption)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                }

                                Spacer()

                                DaylightBadge(
                                    acct.connectionStatus.displayName,
                                    icon: acct.connectionStatus == .cdrRefreshFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                    tone: acct.connectionStatus == .cdrRefreshFailed ? .warning : (acct.connectionStatus == .demoSynthetic ? .demo : .positive)
                                )
                            }

                            if let err = acct.lastSyncErrorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(DaylightTheme.warning)
                                    Text(err)
                                        .font(DaylightTypography.caption)
                                    Spacer()
                                    Button("Retry Sync") {
                                        store.retryAccountSync(accountId: acct.id)
                                    }
                                    .font(DaylightTypography.captionMedium)
                                    .buttonStyle(.borderedProminent)
                                    .tint(DaylightTheme.accent)
                                }
                                .padding(DaylightTheme.Spacing.sm)
                                .background(RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm).fill(DaylightTheme.warningSurface(for: colorScheme)))
                            }

                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acct.accountType == .creditCard ? "Available Credit" : "Available Balance")
                                        .font(DaylightTypography.caption)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                    Text(AustralianMoneyFormatter.format(cents: acct.availableBalanceCents))
                                        .font(DaylightTypography.financialAmount(size: 20, weight: .bold))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acct.accountType == .creditCard ? "Current Balance Owing" : "Current Ledger Balance")
                                        .font(DaylightTypography.caption)
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                    Text(AustralianMoneyFormatter.format(cents: acct.currentBalanceCents))
                                        .font(DaylightTypography.financialAmount(size: 18, weight: .semibold))
                                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                }

                                Spacer()
                            }

                            HStack {
                                Text("Coverage: \(acct.dataCoverageDescription) • Updated \(AustralianDateHelper.formatDateTime(acct.balanceUpdatedAt, timeZoneId: store.profile.timeZoneId))")
                                    .font(DaylightTypography.finePrint)
                                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))

                                Spacer()

                                if acct.connectionStatus != .cdrRefreshFailed {
                                    Button("Simulate Sync Timeout") {
                                        store.simulateAccountRefreshFailure(accountId: acct.id)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                }

                                if acct.connectionStatus != .disconnected {
                                    Button("Disconnect", role: .destructive) {
                                        store.disconnectAccountAndRevokeConsent(accountId: acct.id)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var consentRecordsSection: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 10) {
                DaylightSectionHeader(
                    title: "Data Sharing Consents (CDR / Sandbox)",
                    subtitle: "Granular scope & expiry tracking per Australian Privacy Principles"
                )

                if store.consentRecords.isEmpty {
                    Text("No active external data-sharing consents in this workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.consentRecords) { consent in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(consent.institutionName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                DaylightBadge(
                                    consent.revokedAt != nil ? "Revoked" : (consent.isSandboxSimulation ? "Sandbox Simulation" : "Active"),
                                    icon: consent.revokedAt != nil ? "xmark.shield.fill" : "checkmark.shield.fill",
                                    tone: consent.revokedAt != nil ? .overBudget : .demo
                                )
                            }
                            Text("Scopes: \(consent.scopesGranted.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Granted: \(AustralianDateHelper.formatMediumDate(consent.grantedAt, timeZoneId: store.profile.timeZoneId)) • Expires: \(AustralianDateHelper.formatMediumDate(consent.expiresAt, timeZoneId: store.profile.timeZoneId)) • \(consent.statusNote)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
