import SwiftUI
import UniformTypeIdentifiers

public struct TransactionsView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText: String = ""
    @State private var selectedCategory: AustralianCategory? = nil
    @State private var selectedAccountId: UUID? = nil
    @State private var directionFilter: TransactionDirection? = nil
    @State private var dateRangeFilter: DateRangeQuickFilter = .all
    @State private var sortOrder: TransactionSortOrder = .newestFirst
    @State private var isBulkSelectMode: Bool = false
    @State private var selectedIdsForBulk: Set<UUID> = []
    @State private var bulkTargetCategory: AustralianCategory = .groceries
    @State private var selectedTransactionForDetail: TransactionRecord? = nil
    @State private var showingAddManualSheet: Bool = false

    public enum DateRangeQuickFilter: String, CaseIterable, Identifiable {
        case all = "All Dates"
        case today = "Today"
        case currentPeriod = "This Cycle"
        case last30Days = "Last 30 Days"
        case currentFY = "This FY"

        public var id: String { rawValue }
    }

    public enum TransactionSortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case highestAmount = "Highest Amount"
        case lowestAmount = "Lowest Amount"

        public var id: String { rawValue }
    }

    public init(store: DaylightStore) {
        self.store = store
    }

    private var duplicateTransactionIds: Set<UUID> {
        Set(store.duplicateCandidates.map { $0.duplicateTransaction.id })
    }

    private var filteredTransactions: [TransactionRecord] {
        let cal = AustralianDateHelper.calendar(for: store.profile.timeZoneId)
        let todayStart = cal.startOfDay(for: store.referenceDate)
        let fyBounds = AustralianDateHelper.financialYearBounds(for: store.referenceDate, timeZoneId: store.profile.timeZoneId)

        let matches = store.transactions.filter { tx in
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = searchText.lowercased()
                let matchesText = tx.merchantName.lowercased().contains(q)
                    || tx.rawDescription.lowercased().contains(q)
                    || tx.category.displayName.lowercased().contains(q)
                    || tx.userNote.lowercased().contains(q)
                if !matchesText { return false }
            }

            if let cat = selectedCategory ?? store.transactionCategoryDrilldown {
                if tx.category != cat && !tx.splits.contains(where: { $0.category == cat }) {
                    return false
                }
            }

            if let acctId = selectedAccountId, tx.accountId != acctId {
                return false
            }

            if let dir = directionFilter, tx.direction != dir {
                return false
            }

            switch dateRangeFilter {
            case .all:
                break
            case .today:
                let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
                if !(todayStart <= tx.occurredAt && tx.occurredAt < end) { return false }
            case .currentPeriod:
                let bounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(
                    referenceDate: store.referenceDate,
                    profile: store.profile
                )
                if !(bounds.startDate <= tx.occurredAt && tx.occurredAt < bounds.endDate) { return false }
            case .last30Days:
                let thirtyAgo = cal.date(byAdding: .day, value: -30, to: todayStart) ?? todayStart
                let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
                if !(thirtyAgo <= tx.occurredAt && tx.occurredAt < end) { return false }
            case .currentFY:
                let endExclusive = cal.date(byAdding: .day, value: 1, to: fyBounds.end) ?? fyBounds.end
                if !(fyBounds.start <= tx.occurredAt && tx.occurredAt < endExclusive) { return false }
            }

            return true
        }

        switch sortOrder {
        case .newestFirst:
            return matches.sorted { $0.occurredAt > $1.occurredAt }
        case .oldestFirst:
            return matches.sorted { $0.occurredAt < $1.occurredAt }
        case .highestAmount:
            return matches.sorted { $0.amountCents > $1.amountCents }
        case .lowestAmount:
            return matches.sorted { $0.amountCents < $1.amountCents }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                transactionSearchBar
                filterControlsCard

                if !store.duplicateCandidates.isEmpty {
                    duplicateCandidatesSection
                }

                if let undoDesc = store.lastUndoDescription {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(DaylightTheme.accent)
                        Text(undoDesc)
                            .font(.footnote.weight(.medium))
                        Spacer()
                        Button("Undo") {
                            store.undoLastTransactionChange()
                        }
                        .font(.footnote.weight(.bold))
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                            .fill(DaylightTheme.accent.opacity(0.12))
                    )
                }

                if isBulkSelectMode {
                    bulkActionBanner
                }

                transactionsListCard
            }
            .padding(DaylightTheme.Spacing.md)
            .padding(.bottom, DaylightTheme.Spacing.bottomNavInset)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Transactions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showingCategoriesManagerSheet = true
                } label: {
                    Label("Categories", systemImage: "tag")
                }

                Button {
                    isBulkSelectMode.toggle()
                    if !isBulkSelectMode {
                        selectedIdsForBulk.removeAll()
                    }
                } label: {
                    Label(isBulkSelectMode ? "Done Selecting" : "Bulk Categorise", systemImage: "checkmark.circle")
                }

                Button {
                    store.showingStatementImporter = true
                } label: {
                    Label("Import CSV", systemImage: "tray.and.arrow.down")
                }

                Button {
                    showingAddManualSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $selectedTransactionForDetail) { tx in
            TransactionDetailSheet(store: store, transaction: tx)
        }
        .sheet(isPresented: $showingAddManualSheet) {
            ManualTransactionSheet(store: store)
        }
    }

    private var transactionSearchBar: some View {
        HStack(spacing: DaylightTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "Search merchant, description, Opal, Woolworths...",
                text: $searchText
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(DaylightTypography.body)
        .padding(.horizontal, DaylightTheme.Spacing.md)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? DaylightTheme.Glass.translucent
                        : DaylightTheme.lightCream.opacity(0.9)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                .stroke(DaylightTheme.Glass.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transaction search")
    }

    // MARK: - Filter Controls Card

    private var filterControlsCard: some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 10) {
                if let drilldown = store.transactionCategoryDrilldown {
                    HStack {
                        DaylightBadge("Drill-down: \(drilldown.displayName)", icon: drilldown.symbolName, tone: .neutral)
                        Spacer()
                        Button("Clear Drill-down") {
                            store.transactionCategoryDrilldown = nil
                        }
                        .font(DaylightTypography.captionMedium)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(DateRangeQuickFilter.allCases) { item in
                                Button {
                                    dateRangeFilter = item
                                } label: {
                                    if item == dateRangeFilter {
                                        Label(item.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(item.rawValue)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(dateRangeFilter.rawValue, icon: "calendar")
                        }

                        Menu {
                            Button {
                                selectedCategory = nil
                            } label: {
                                if selectedCategory == nil {
                                    Label("All Categories", systemImage: "checkmark")
                                } else {
                                    Text("All Categories")
                                }
                            }
                            ForEach(AustralianCategory.allCases) { cat in
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    if selectedCategory == cat {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(
                                selectedCategory?.displayName ?? "All Categories",
                                icon: selectedCategory?.symbolName ?? "tag"
                            )
                        }

                        Menu {
                            Button {
                                selectedAccountId = nil
                            } label: {
                                if selectedAccountId == nil {
                                    Label("All Accounts", systemImage: "checkmark")
                                } else {
                                    Text("All Accounts")
                                }
                            }
                            ForEach(store.accounts) { acct in
                                Button {
                                    selectedAccountId = acct.id
                                } label: {
                                    if selectedAccountId == acct.id {
                                        Label(acct.nickname, systemImage: "checkmark")
                                    } else {
                                        Text(acct.nickname)
                                    }
                                }
                            }
                        } label: {
                            let acctLabel = store.accounts.first(where: { $0.id == selectedAccountId })?.nickname ?? "All Accounts"
                            DaylightDropdownPill(acctLabel, icon: "building.columns")
                        }

                        Menu {
                            Button {
                                directionFilter = nil
                            } label: {
                                if directionFilter == nil {
                                    Label("All Types", systemImage: "checkmark")
                                } else {
                                    Text("All Types")
                                }
                            }
                            Button {
                                directionFilter = .debit
                            } label: {
                                if directionFilter == .debit {
                                    Label("Expenses", systemImage: "checkmark")
                                } else {
                                    Text("Expenses")
                                }
                            }
                            Button {
                                directionFilter = .credit
                            } label: {
                                if directionFilter == .credit {
                                    Label("Income", systemImage: "checkmark")
                                } else {
                                    Text("Income")
                                }
                            }
                        } label: {
                            let dirLabel = directionFilter == nil ? "All Types" : (directionFilter == .debit ? "Expenses" : "Income")
                            DaylightDropdownPill(dirLabel, icon: "arrow.up.arrow.down")
                        }

                        Menu {
                            ForEach(TransactionSortOrder.allCases) { order in
                                Button {
                                    sortOrder = order
                                } label: {
                                    if order == sortOrder {
                                        Label(order.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(order.rawValue)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(sortOrder.rawValue, icon: "arrow.up.and.down.text.horizontal")
                        }

                        if selectedCategory != nil || store.transactionCategoryDrilldown != nil || selectedAccountId != nil || directionFilter != nil || dateRangeFilter != .all || !searchText.isEmpty {
                            Button("Reset") {
                                selectedCategory = nil
                                store.transactionCategoryDrilldown = nil
                                selectedAccountId = nil
                                directionFilter = nil
                                dateRangeFilter = .all
                                searchText = ""
                            }
                            .font(DaylightTypography.captionMedium)
                        }
                    }
                }

                let activeCategoryFilter = selectedCategory ?? store.transactionCategoryDrilldown
                let netOutflow = filteredTransactions.reduce(MoneyCents(0)) { total, tx in
                    guard tx.direction == .debit else { return total }
                    return total + attributedAmount(for: tx, category: activeCategoryFilter)
                }
                let netInflow = filteredTransactions.reduce(MoneyCents(0)) { total, tx in
                    guard tx.direction == .credit else { return total }
                    return total + attributedAmount(for: tx, category: activeCategoryFilter)
                }

                HStack {
                    Text("\(filteredTransactions.count) transaction\(filteredTransactions.count == 1 ? "" : "s")")
                        .font(DaylightTypography.captionMedium)
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Text("Outflows: \(AustralianMoneyFormatter.format(cents: netOutflow)) • Inflows: \(AustralianMoneyFormatter.format(cents: netInflow))")
                        .font(DaylightTypography.captionMedium)
                        .monospacedDigit()
                        .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                }

            }
        }
    }

    private func attributedAmount(for transaction: TransactionRecord, category: AustralianCategory?) -> MoneyCents {
        guard transaction.status == .posted || transaction.status == .refunded,
              transaction.kind != .ownAccountTransfer,
              transaction.kind != .creditCardRepayment else { return 0 }
        guard let category else { return transaction.amountCents }
        guard !transaction.splits.isEmpty else {
            return transaction.category == category ? transaction.amountCents : 0
        }
        return transaction.splits
            .filter { $0.category == category && !$0.excludeFromBudget }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var bulkActionBanner: some View {
        DaylightCard(padding: DaylightTheme.Spacing.sm) {
            HStack(spacing: 12) {
                Text("\(selectedIdsForBulk.count) selected")
                    .font(DaylightTypography.subheadlineMedium)

                Menu {
                    ForEach(AustralianCategory.allCases) { cat in
                        Button {
                            bulkTargetCategory = cat
                        } label: {
                            if cat == bulkTargetCategory {
                                Label(cat.displayName, systemImage: "checkmark")
                            } else {
                                Text(cat.displayName)
                            }
                        }
                    }
                } label: {
                    DaylightDropdownPill(bulkTargetCategory.displayName, icon: bulkTargetCategory.symbolName)
                }

                Spacer()

                Button("Apply") {
                    store.bulkCategoriseTransactions(ids: selectedIdsForBulk, newCategory: bulkTargetCategory)
                    selectedIdsForBulk.removeAll()
                    isBulkSelectMode = false
                }
                .font(DaylightTypography.captionMedium)
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
                .disabled(selectedIdsForBulk.isEmpty)
            }
        }
    }

    // MARK: - Transactions List Card

    private var transactionsListCard: some View {
        DaylightCard(padding: 0) {
            if filteredTransactions.isEmpty {
                DaylightEmptyState(
                    icon: "magnifyingglass",
                    title: "No transactions match your current filters",
                    message: "Try clearing a filter, importing a CSV bank statement, or adding a transaction manually.",
                    actionTitle: "Import CSV Statement"
                ) {
                    store.showingStatementImporter = true
                }
                .padding(DaylightTheme.Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Transactions")
                            .font(DaylightTypography.cardTitle)

                        Spacer()

                        Text("\(filteredTransactions.count) results")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, DaylightTheme.Spacing.md)
                    .padding(.vertical, DaylightTheme.Spacing.sm)

                    Divider()

                    LazyVStack(spacing: 0) {
                        ForEach(filteredTransactions) { tx in
                            let accountName = store.accounts.first(where: { $0.id == tx.accountId })?.nickname ?? "Account"

                            HStack(spacing: DaylightTheme.Spacing.sm) {
                                if isBulkSelectMode {
                                    Button {
                                        if selectedIdsForBulk.contains(tx.id) {
                                            selectedIdsForBulk.remove(tx.id)
                                        } else {
                                            selectedIdsForBulk.insert(tx.id)
                                        }
                                    } label: {
                                        Image(systemName: selectedIdsForBulk.contains(tx.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(DaylightTheme.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        selectedIdsForBulk.contains(tx.id)
                                            ? "Deselect \(tx.merchantName)"
                                            : "Select \(tx.merchantName)"
                                    )
                                }

                                Image(systemName: tx.category.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tx.category.tintColor)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(tx.category.tintColor.opacity(0.14)))

                                Button {
                                    selectedTransactionForDetail = tx
                                } label: {
                                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xxs) {
                                        HStack(spacing: DaylightTheme.Spacing.xxs) {
                                            Text(tx.merchantName)
                                                .font(DaylightTypography.transactionTitle)
                                                .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                                                .lineLimit(1)

                                            if tx.isRecurring {
                                                Image(systemName: "repeat.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(DaylightTheme.accent)
                                                    .help("Recurring payment")
                                            }

                                            if tx.classificationConfidence < 0.70 {
                                                DaylightBadge("Review", icon: "questionmark.circle", tone: .warning)
                                            }

                                            if duplicateTransactionIds.contains(tx.id) {
                                                DaylightBadge("Duplicate", icon: "doc.on.doc", tone: .warning)
                                            }
                                        }

                                        Text("\(tx.category.displayName) • \(accountName)")
                                            .font(DaylightTypography.transactionMetadata)
                                            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Shows transaction details")

                                Text(
                                    AustralianMoneyFormatter.format(
                                        cents: tx.direction == .debit ? -tx.amountCents : tx.amountCents,
                                        showPlusForPositive: true
                                    )
                                )
                                .font(DaylightTypography.transactionAmount)
                                .foregroundStyle(tx.direction == .credit ? DaylightTheme.positive : DaylightTheme.primaryText(for: colorScheme))
                            }
                            .padding(.horizontal, DaylightTheme.Spacing.md)
                            .padding(.vertical, DaylightTheme.Spacing.xs)

                            Divider()
                                .padding(.leading, isBulkSelectMode ? 118 : 78)
                        }
                    }
                }
            }
        }
    }

    private var duplicateCandidatesSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
            HStack(spacing: DaylightTheme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DaylightTheme.warning)
                Text("Potential Duplicate Transactions (\(store.duplicateCandidates.count))")
                    .font(DaylightTypography.sectionTitle)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                Spacer()
            }

            Text("Daylight detected potential duplicate transactions. Please review them below. Transactions are never deleted automatically.")
                .font(DaylightTypography.caption)
                .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))

            ForEach(store.duplicateCandidates) { group in
                DuplicateCandidateCard(
                    group: group,
                    store: store,
                    onInspect: {
                        selectedTransactionForDetail = group.duplicateTransaction
                    }
                )
            }
        }
        .padding(DaylightTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.lg)
                .fill(DaylightTheme.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.lg)
                        .stroke(DaylightTheme.warning.opacity(0.2), lineWidth: 1)
                )
        )
    }
}


// MARK: - Transaction Detail & Split Editor Sheet

public struct TransactionDetailSheet: View {
    @Bindable var store: DaylightStore
    let transaction: TransactionRecord
    @Environment(\.dismiss) private var dismiss

    @State private var merchantName: String = ""
    @State private var amountDollars: String = ""
    @State private var direction: TransactionDirection = .debit
    @State private var occurredAt: Date = Date()
    @State private var category: AustralianCategory = .groceries
    @State private var selectedCustomCategoryName: String = ""
    @State private var kind: TransactionKind = .expense
    @State private var status: TransactionStatus = .posted
    @State private var userNote: String = ""
    @State private var excludeFromBudget: Bool = false
    @State private var saveMerchantRuleForFuture: Bool = false
    @State private var splits: [TransactionSplit] = []
    @State private var splitPart1Dollars: String = ""
    @State private var splitPart1Category: AustralianCategory = .groceries
    @State private var splitPart2Category: AustralianCategory = .shoppingRetail
    @State private var showingDeleteConfirmation: Bool = false
    @State private var errorMessage: String? = nil
    @State private var applyToUnconfirmed: Bool = true

    public var body: some View {
        NavigationStack {
            Form {
                Section("Transaction Amount, Date & Source") {
                    TextField("Amount (AUD)", text: $amountDollars)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .monospacedDigit()

                    Picker("Direction", selection: $direction) {
                        Text("Expense").tag(TransactionDirection.debit)
                        Text("Income").tag(TransactionDirection.credit)
                    }
                    .pickerStyle(.segmented)

                    DatePicker("Occurred At", selection: $occurredAt)

                    LabeledContent("Original Bank Description", value: transaction.rawDescription)
                    LabeledContent("Data Source", value: transaction.source.displayName)
                }

                TransactionIntelligenceSectionView(
                    transaction: transaction,
                    merchantName: $merchantName,
                    direction: $direction,
                    category: $category,
                    kind: $kind,
                    userRules: store.merchantRules
                )

                Section("Merchant, Category & Rule") {
                    TextField("Merchant or Payee Name", text: $merchantName)

                    HStack {
                        Text("Category")
                        Spacer()
                        Menu {
                            ForEach(AustralianCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    if cat == category {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(category.displayName, icon: category.symbolName)
                        }
                    }

                    let customCats = store.customCategories(includeArchived: false)
                    if !customCats.isEmpty {
                        HStack {
                            Text("Custom Tag")
                            Spacer()
                            Menu {
                                Button("None") { selectedCustomCategoryName = "" }
                                ForEach(customCats) { custom in
                                    Button(custom.name) { selectedCustomCategoryName = custom.name }
                                }
                            } label: {
                                DaylightDropdownPill(
                                    selectedCustomCategoryName.isEmpty ? "None" : selectedCustomCategoryName,
                                    icon: "tag"
                                )
                            }
                        }
                    }
                    HStack {
                        Text("Rule")
                        Spacer()
                        Menu {
                            ForEach(TransactionKind.allCases) { item in
                                Button {
                                    kind = item
                                } label: {
                                    if item == kind {
                                        Label(item.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(item.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(kind.displayName)
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Menu {
                            ForEach(TransactionStatus.allCases) { st in
                                Button {
                                    status = st
                                } label: {
                                    if st == status {
                                        Label(st.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(st.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(status.displayName)
                        }
                    }
                    Toggle("Exclude from Flexible Budget Calculations", isOn: $excludeFromBudget)
                    Toggle("Always categorise '\(merchantName)' as \(category.displayName) for future imports", isOn: $saveMerchantRuleForFuture)
                    if category != transaction.category {
                        Toggle("Apply correction to existing unconfirmed transactions", isOn: $applyToUnconfirmed)
                    }
                }

                Section("Notes") {
                    TextField("Add personal note or receipt context...", text: $userNote)
                }

                Section("Split Transaction Across Two Categories (Optional)") {
                    if splits.isEmpty {
                        Text("Splitting lets you divide a single purchase (e.g. $100 at Woolworths or Bunnings) across two categories while keeping the exact total.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("First Split Amount (AUD, out of \(AustralianMoneyFormatter.format(cents: transaction.amountCents)))", text: $splitPart1Dollars)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Picker("1st Split Category", selection: $splitPart1Category) {
                            ForEach(AustralianCategory.allCases) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        Picker("2nd Split Category", selection: $splitPart2Category) {
                            ForEach(AustralianCategory.allCases) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        Button("Create 2-Way Split") {
                            createTwoWaySplit()
                        }
                        .disabled(AustralianMoneyFormatter.parseToCents(splitPart1Dollars) == nil)
                    } else {
                        ForEach(splits) { split in
                            HStack {
                                Text(split.category.displayName)
                                Spacer()
                                Text(AustralianMoneyFormatter.format(cents: split.amountCents))
                                    .monospacedDigit()
                            }
                        }
                        Button("Remove Split & Restore Single Category", role: .destructive) {
                            splits.removeAll()
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Transaction", systemImage: "trash")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("delete_transaction_button")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(DaylightTheme.cautionRed)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Transaction Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete '\(transaction.merchantName)'?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Transaction", role: .destructive) {
                    do {
                        try store.deleteTransaction(id: transaction.id)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \(transaction.merchantName) (\(AustralianMoneyFormatter.format(cents: transaction.amountCents))) from your workspace. You can undo this immediately from the Transactions screen.")
            }
            .onAppear {
                merchantName = transaction.merchantName
                amountDollars = String(format: "%.2f", Double(transaction.amountCents) / 100.0)
                direction = transaction.direction
                occurredAt = transaction.occurredAt
                category = transaction.category
                kind = transaction.kind
                status = transaction.status
                userNote = transaction.userNote
                excludeFromBudget = transaction.excludeFromBudget
                splits = transaction.splits
                let halfCents = transaction.amountCents / 2
                splitPart1Dollars = String(format: "%.2f", Double(halfCents) / 100.0)
                splitPart1Category = transaction.category
            }
        }
    }

    private func createTwoWaySplit() {
        let totalCents = AustralianMoneyFormatter.parseToCents(amountDollars) ?? transaction.amountCents
        guard let part1 = AustralianMoneyFormatter.parseToCents(splitPart1Dollars),
              part1 > 0,
              part1 < totalCents else {
            errorMessage = "First split amount must be between $0.01 and \(AustralianMoneyFormatter.format(cents: max(1, totalCents - 1)))."
            return
        }
        let part2 = totalCents - part1
        splits = [
            TransactionSplit(id: UUID(), category: splitPart1Category, amountCents: part1, note: "Split 1", excludeFromBudget: false),
            TransactionSplit(id: UUID(), category: splitPart2Category, amountCents: part2, note: "Split 2", excludeFromBudget: false)
        ]
        errorMessage = nil
    }

    private func saveChanges() {
        guard let parsedCents = AustralianMoneyFormatter.parseToCents(amountDollars), parsedCents > 0 else {
            errorMessage = "Please enter a valid positive AUD amount."
            return
        }
        var updated = transaction
        updated.merchantName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transaction.merchantName : merchantName
        updated.amountCents = parsedCents
        updated.direction = direction
        updated.occurredAt = occurredAt
        updated.category = category
        updated.kind = kind
        updated.status = status
        let cleanedNote = store.customCategories(includeArchived: true)
            .reduce(userNote) { note, customCategory in
                note.replacingOccurrences(of: "[\(customCategory.name)]", with: "")
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedCustomCategoryName.isEmpty {
            updated.userNote = cleanedNote.isEmpty ? "[\(selectedCustomCategoryName)]" : "[\(selectedCustomCategoryName)] \(cleanedNote)"
        } else {
            updated.userNote = cleanedNote
        }
        updated.excludeFromBudget = excludeFromBudget
        updated.splits = splits

        do {
            try store.updateTransaction(
                updated,
                createMerchantRuleForFuture: saveMerchantRuleForFuture || applyToUnconfirmed,
                applyCategoryToUnconfirmed: applyToUnconfirmed && category != transaction.category
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Transaction Intelligence Section Subview

private struct TransactionIntelligenceSectionView: View {
    let transaction: TransactionRecord
    @Binding var merchantName: String
    @Binding var direction: TransactionDirection
    @Binding var category: AustralianCategory
    @Binding var kind: TransactionKind
    let userRules: [MerchantRule]

    private var recognition: RecognizedMerchant {
        let rawTarget = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? transaction.rawDescription
            : merchantName
        return MerchantRecognitionService.shared.recognise(rawTarget)
    }

    private var classification: IntelligentClassificationResult {
        let rawTarget = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? transaction.rawDescription
            : merchantName
        return IntelligentCategorisationEngine.shared.classify(
            rawDescription: rawTarget,
            direction: direction,
            isCreditCardAccount: false,
            userRules: userRules
        )
    }

    private var badgeTone: FinancialBadgeTone {
        if classification.confidence >= 0.85 {
            return .positive
        } else if classification.confidence >= 0.70 {
            return .neutral
        } else {
            return .warning
        }
    }

    private var confidenceColor: Color {
        if classification.confidence >= 0.85 {
            return DaylightTheme.positive
        } else if classification.confidence >= 0.70 {
            return DaylightTheme.accent
        } else {
            return DaylightTheme.warning
        }
    }

    var body: some View {
        Section("Transaction Intelligence") {
            HStack {
                Text("Recognised Merchant")
                Spacer()
                Text(recognition.recognisedName)
                    .foregroundStyle(.secondary)
                if recognition.recognisedName != merchantName && !recognition.isUnknown {
                    Button("Apply") {
                        merchantName = recognition.recognisedName
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Text("Suggested Category")
                Spacer()
                DaylightBadge(
                    classification.suggestedCategory.displayName,
                    icon: classification.suggestedCategory.symbolName,
                    tone: badgeTone
                )
                if classification.suggestedCategory != category {
                    Button("Use Suggestion") {
                        category = classification.suggestedCategory
                        kind = classification.suggestedKind
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack {
                Text("Confidence Score")
                Spacer()
                Text("\(Int(classification.confidence * 100))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(confidenceColor)
            }

            LabeledContent("Source", value: classification.source.displayName)
            LabeledContent("Reason", value: classification.reason)

            if classification.isManualReviewRecommended {
                HStack(spacing: DaylightTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(DaylightTheme.warning)
                    Text("Manual review recommended due to lower confidence.")
                        .font(DaylightTypography.caption)
                        .foregroundStyle(DaylightTheme.warning)
                }
            }
        }
    }
}

// MARK: - Manual Transaction Entry Sheet

public struct ManualTransactionSheet: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss

    @State private var merchantName: String = ""
    @State private var amountDollars: String = ""
    @State private var direction: TransactionDirection = .debit
    @State private var category: AustralianCategory = .groceries
    @State private var selectedCustomCategoryName: String = ""
    @State private var kind: TransactionKind = .expense
    @State private var selectedAccountId: UUID = UUID()
    @State private var occurredAt: Date = Date()
    @State private var userNote: String = ""
    @State private var excludeFromBudget: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submissionIdempotencyKey: String = "manual-tx-\(UUID().uuidString)"
    @State private var errorMessage: String? = nil

    public var body: some View {
        NavigationStack {
            Form {
                Section("Transaction Details") {
                    TextField("Merchant or Payee (e.g. Woolworths, Opal, Rent)", text: $merchantName)
                        .onChange(of: merchantName) { _, newValue in
                            let classified = IntelligentCategorisationEngine.shared.classify(
                                rawDescription: newValue,
                                direction: direction,
                                isCreditCardAccount: false,
                                userRules: store.merchantRules
                            )
                            if classified.confidence >= 0.70 {
                                category = classified.suggestedCategory
                                kind = classified.suggestedKind
                            }
                        }

                    TextField("Amount in AUD (e.g. 18.50)", text: $amountDollars)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif

                    Picker("Direction", selection: $direction) {
                        Text("Expense").tag(TransactionDirection.debit)
                        Text("Income").tag(TransactionDirection.credit)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Category")
                        Spacer()
                        Menu {
                            ForEach(AustralianCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    if cat == category {
                                        Label(cat.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(cat.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(category.displayName, icon: category.symbolName)
                        }
                    }

                    let customCats = store.customCategories(includeArchived: false)
                    if !customCats.isEmpty {
                        HStack {
                            Text("Custom Tag")
                            Spacer()
                            Menu {
                                Button("None") { selectedCustomCategoryName = "" }
                                ForEach(customCats) { custom in
                                    Button(custom.name) { selectedCustomCategoryName = custom.name }
                                }
                            } label: {
                                DaylightDropdownPill(
                                    selectedCustomCategoryName.isEmpty ? "None" : selectedCustomCategoryName,
                                    icon: "tag"
                                )
                            }
                        }
                    }

                    Button {
                        store.showingCategoriesManagerSheet = true
                    } label: {
                        Label("Manage Custom Categories…", systemImage: "tag")
                            .font(.caption.weight(.semibold))
                    }

                    HStack {
                        Text("Rule")
                        Spacer()
                        Menu {
                            ForEach(TransactionKind.allCases) { k in
                                Button {
                                    kind = k
                                } label: {
                                    if k == kind {
                                        Label(k.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(k.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(kind.displayName)
                        }
                    }

                    if !store.accounts.isEmpty {
                        HStack {
                            Text("Account")
                            Spacer()
                            Menu {
                                ForEach(store.accounts) { acct in
                                    Button {
                                        selectedAccountId = acct.id
                                    } label: {
                                        if acct.id == selectedAccountId {
                                            Label(acct.nickname, systemImage: "checkmark")
                                        } else {
                                            Text(acct.nickname)
                                        }
                                    }
                                }
                            } label: {
                                let acctLabel = store.accounts.first(where: { $0.id == selectedAccountId })?.nickname ?? "Select Account"
                                DaylightDropdownPill(acctLabel, icon: "building.columns")
                            }
                        }
                    }

                    DatePicker("Date & Time", selection: $occurredAt)
                }

                Section("Optional Note & Budget Inclusion") {
                    TextField("Note (optional)", text: $userNote)
                    Toggle("Exclude from Daily Safe-to-Spend Budget", isOn: $excludeFromBudget)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(DaylightTheme.cautionRed)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        submitTransaction()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSubmitting)
                }
            }
            .onAppear {
                store.refreshWorkspaceCategories()
                if let firstId = store.accounts.first?.id {
                    selectedAccountId = firstId
                }
            }
        }
    }

    private func submitTransaction() {
        guard !isSubmitting else { return }
        let trimmedMerchant = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            errorMessage = "Please enter a merchant or payee name."
            return
        }
        guard let cents = AustralianMoneyFormatter.parseToCents(amountDollars), cents > 0 else {
            errorMessage = "Please enter a positive AUD amount (e.g. 24.50)."
            return
        }
        isSubmitting = true
        let finalNote: String
        if !selectedCustomCategoryName.isEmpty {
            finalNote = userNote.isEmpty ? "[\(selectedCustomCategoryName)]" : "[\(selectedCustomCategoryName)] \(userNote)"
        } else {
            finalNote = userNote
        }

        do {
            try store.addManualTransaction(
                accountId: selectedAccountId,
                merchantName: trimmedMerchant,
                rawDescription: trimmedMerchant,
                amountCents: cents,
                direction: direction,
                category: category,
                kind: kind,
                occurredAt: occurredAt,
                userNote: finalNote,
                excludeFromBudget: excludeFromBudget,
                idempotencyKey: submissionIdempotencyKey
            )
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Interactive CSV Statement Import Wizard (14-Step Verified Workflow)

public struct StatementImportSheet: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String = "Australian_Bank_Statement_Oct2026.csv"
    @State private var csvInputText: String = ""
    @State private var targetAccountId: UUID = UUID()
    @State private var detectedHeaders: [String] = []
    @State private var mapping = CSVColumnMapping(dateColumnIndex: 0, descriptionColumnIndex: 1, amountColumnIndex: 2, debitColumnIndex: nil, creditColumnIndex: nil, hasHeaderRow: true)
    @State private var dateFormatPreference: String = "Auto-Detect AU (DD/MM/YYYY & ISO)"
    @State private var showingSystemFileImporter: Bool = false
    @State private var previewRows: [ParsedCSVRowPreview] = []
    @State private var completedJob: ImportJobRecord? = nil
    @State private var errorMessage: String? = nil
    @State private var repairingRow: ParsedCSVRowPreview? = nil
    @State private var repairDateText: String = ""
    @State private var repairDescriptionText: String = ""
    @State private var repairAmountText: String = ""
    @State private var repairDirection: TransactionDirection = .debit
    @State private var repairErrorMessage: String? = nil

    private let dateFormatOptions = [
        "Auto-Detect AU (DD/MM/YYYY & ISO)",
        "DD/MM/YYYY (Australian Standard)",
        "YYYY-MM-DD (ISO 8601)",
        "D MMM YYYY (14 Oct 2026)"
    ]

    public init(store: DaylightStore) {
        self.store = store
    }

    private var validReadyRowsCount: Int {
        previewRows.filter { $0.validationError == nil && !$0.isDuplicate }.count
    }

    private var duplicateRowsCount: Int {
        previewRows.filter { $0.isDuplicate }.count
    }

    private var rejectedRowsCount: Int {
        previewRows.filter { $0.validationError != nil }.count
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                    DaylightCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                DaylightBadge("CSV Statement Importer", icon: "doc.text.magnifyingglass", tone: .neutral)
                                Spacer()
                                Text("Max size: 10 MB • Untrusted input sanitised")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Import Australian Bank Statements Safely")
                                .font(.headline)
                            Text("Supports CommBank, NAB, ANZ, Westpac, Macquarie, Up, and standard Australian CSV exports (DD/MM/YYYY dates). Legitimate same-day identical purchases are preserved, while re-importing the same statement skips duplicates automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let job = completedJob {
                        importSuccessSummaryCard(job)
                    } else {
                        step1InputCard
                        if !previewRows.isEmpty {
                            step2ColumnMappingCard
                            step3PreviewAndReconciliationCard
                        }
                    }
                }
                .padding(DaylightTheme.Spacing.md)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Statement Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $repairingRow) { row in
                rejectedRowRepairSheet(row)
            }
            .onAppear {
                if let firstAcct = store.accounts.first?.id {
                    targetAccountId = firstAcct
                }
                loadSampleCSV()
            }
            .fileImporter(
                isPresented: $showingSystemFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleSelectedCSVFile(result)
            }
        }
    }

    private var step1InputCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("1. Statement Source & Target Account")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        showingSystemFileImporter = true
                    } label: {
                        Label("Choose CSV File…", systemImage: "folder.badge.plus")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)

                    Button("Load Sample AU CSV") {
                        loadSampleCSV()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }

                if !store.accounts.isEmpty {
                    HStack {
                        Text("Target Account")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Menu {
                            ForEach(store.accounts) { acct in
                                Button {
                                    targetAccountId = acct.id
                                    refreshPreview()
                                } label: {
                                    if acct.id == targetAccountId {
                                        Label(acct.nickname, systemImage: "checkmark")
                                    } else {
                                        Text(acct.nickname)
                                    }
                                }
                            }
                        } label: {
                            let acctLabel = store.accounts.first(where: { $0.id == targetAccountId })?.nickname ?? "Select Account"
                            DaylightDropdownPill(acctLabel, icon: "building.columns")
                        }
                    }
                }

                TextField("Statement Filename", text: $fileName)
                    .textFieldStyle(.roundedBorder)

                Text("CSV Content (Select a file above, or paste/edit rows to test parsing, duplicate detection, and rejected row handling):")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextEditor(text: $csvInputText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 130)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .onChange(of: csvInputText) { _, _ in
                        refreshPreview()
                    }
            }
        }
    }

    private var step2ColumnMappingCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("2. Column Mapping, Date Format & Header Detection")
                    .font(.subheadline.weight(.semibold))

                Toggle("First row contains column headers", isOn: $mapping.hasHeaderRow)
                    .font(.caption)
                    .onChange(of: mapping.hasHeaderRow) { _, _ in refreshPreview() }

                HStack {
                    Text("Date Format")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Menu {
                        ForEach(dateFormatOptions, id: \.self) { fmt in
                            Button {
                                dateFormatPreference = fmt
                                refreshPreview()
                            } label: {
                                if fmt == dateFormatPreference {
                                    Label(fmt, systemImage: "checkmark")
                                } else {
                                    Text(fmt)
                                }
                            }
                        }
                    } label: {
                        DaylightDropdownPill(dateFormatPreference, icon: "calendar")
                    }
                }

                HStack(spacing: 16) {
                    Stepper("Date Col: \(mapping.dateColumnIndex + 1)", value: $mapping.dateColumnIndex, in: 0...max(0, detectedHeaders.count - 1)) { _ in
                        refreshPreview()
                    }
                    Stepper("Desc Col: \(mapping.descriptionColumnIndex + 1)", value: $mapping.descriptionColumnIndex, in: 0...max(0, detectedHeaders.count - 1)) { _ in
                        refreshPreview()
                    }
                }
                .font(.caption)
            }
        }
    }

    private var step3PreviewAndReconciliationCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("3. Preview & Duplicate Reconciliation")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    DaylightBadge("\(validReadyRowsCount) Ready", icon: "checkmark.circle.fill", tone: .positive)
                    if duplicateRowsCount > 0 {
                        DaylightBadge("\(duplicateRowsCount) Duplicate", icon: "doc.on.doc.fill", tone: .warning)
                    }
                    if rejectedRowsCount > 0 {
                        DaylightBadge("\(rejectedRowsCount) Rejected", icon: "exclamationmark.triangle.fill", tone: .overBudget)
                    }
                }

                ForEach(previewRows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Row #\(row.rowNumber): \(row.parsedDescription.isEmpty ? row.rawLine : row.parsedDescription)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let err = row.validationError {
                                HStack(spacing: 6) {
                                    Text("Rejected: \(err)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DaylightTheme.cautionRed)
                                    Button("Fix & Retry Row") {
                                        beginRejectedRowRepair(row)
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .buttonStyle(.bordered)
                                }
                            } else if row.isDuplicate {
                                Text("Duplicate (Skipped)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(DaylightTheme.warning)
                            } else if let cents = row.parsedAmountCents {
                                Text(AustralianMoneyFormatter.format(cents: row.parsedDirection == .debit ? -cents : cents, showPlusForPositive: true))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                            }
                        }
                        if row.validationError == nil {
                            Text("Category: \(row.inferredCategory.displayName) • Rule: \(row.inferredKind.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(DaylightTheme.cautionRed)
                }

                Button {
                    commitImport()
                } label: {
                    Text("Confirm & Import \(validReadyRowsCount) Transaction\(validReadyRowsCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
                .disabled(validReadyRowsCount == 0)
            }
        }
    }

    private func importSuccessSummaryCard(_ job: ImportJobRecord) -> some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(DaylightTheme.positive)
                    Text("Import Completed Safely")
                        .font(.headline)
                }

                Text("Imported \(job.importedCount) new transactions into your workspace. \(job.duplicateSkippedCount) duplicates were skipped and \(job.rejectedCount) invalid rows were rejected without corrupting your ledger.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Import Another File") {
                        completedJob = nil
                        refreshPreview()
                    }
                    .buttonStyle(.bordered)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)
                }
            }
        }
    }

    private func handleSelectedCSVFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Could not open CSV file: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                if let size = resourceValues.fileSize, size > 10 * 1024 * 1024 {
                    errorMessage = "Statement file exceeds the 10 MB safety limit."
                    return
                }
                let data = try Data(contentsOf: url)
                let decodedText = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .windowsCP1252)
                    ?? String(data: data, encoding: .isoLatin1)
                guard let text = decodedText else {
                    errorMessage = "Unsupported file encoding. Please export your bank statement as UTF-8 CSV."
                    return
                }
                fileName = url.lastPathComponent
                csvInputText = text
                let detected = FinancialCalculationEngine.detectCSVColumnMapping(csvText: text)
                detectedHeaders = detected.headers
                mapping = detected.mapping
                errorMessage = nil
                refreshPreview()
            } catch {
                errorMessage = "Failed to read selected CSV file: \(error.localizedDescription)"
            }
        }
    }

    private func beginRejectedRowRepair(_ row: ParsedCSVRowPreview) {
        repairingRow = row
        repairDateText = ""
        repairDescriptionText = row.parsedDescription
        repairAmountText = row.parsedAmountCents.map { AustralianMoneyFormatter.format(cents: $0) } ?? ""
        repairDirection = row.parsedDirection
        repairErrorMessage = nil
    }

    private func rejectedRowRepairSheet(_ row: ParsedCSVRowPreview) -> some View {
        NavigationStack {
            Form {
                Section("Corrected Values") {
                    TextField("Date (DD/MM/YYYY)", text: $repairDateText)
                    TextField("Description", text: $repairDescriptionText)
                    TextField("Amount (AUD)", text: $repairAmountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Direction", selection: $repairDirection) {
                        Text("Expense").tag(TransactionDirection.debit)
                        Text("Income").tag(TransactionDirection.credit)
                    }
                    .pickerStyle(.segmented)
                }

                if let repairErrorMessage {
                    Section {
                        Text(repairErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(DaylightTheme.cautionRed)
                    }
                }

                Section {
                    Text("The original CSV row is preserved until you confirm this repair.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Repair Row #\(row.rowNumber)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { repairingRow = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyRejectedRowRepair(row) }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func applyRejectedRowRepair(_ row: ParsedCSVRowPreview) {
        let trimmedDescription = repairDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = FinancialCalculationEngine.parseAustralianBankDate(
            repairDateText,
            timeZoneId: store.profile.timeZoneId
        ) else {
            repairErrorMessage = "Enter a valid date such as 14/10/2026."
            return
        }
        guard let cents = AustralianMoneyFormatter.parseToCents(repairAmountText), cents > 0 else {
            repairErrorMessage = "Enter a positive monetary amount."
            return
        }
        guard !trimmedDescription.isEmpty else {
            repairErrorMessage = "Enter a transaction description."
            return
        }

        let isCreditCard = store.accounts.first(where: { $0.id == targetAccountId })?.accountType == .creditCard
        let classification = FinancialCalculationEngine.classifyAustralianTransaction(
            rawDescription: trimmedDescription,
            direction: repairDirection,
            isCreditCardAccount: isCreditCard,
            userMerchantRules: store.merchantRules
        )
        let fingerprint = FinancialCalculationEngine.makeReconciliationFingerprint(
            accountId: targetAccountId,
            date: date,
            amountCents: cents,
            direction: repairDirection,
            rawDescription: trimmedDescription,
            sourceTransactionId: nil,
            occurrenceIndexInBatch: row.rowNumber
        )
        let repaired = ParsedCSVRowPreview(
            id: row.id,
            rowNumber: row.rowNumber,
            rawLine: row.rawLine,
            parsedDate: date,
            parsedDescription: trimmedDescription,
            parsedAmountCents: cents,
            parsedDirection: repairDirection,
            inferredCategory: classification.category,
            inferredKind: classification.kind,
            classificationConfidence: classification.confidence,
            fingerprint: fingerprint,
            isDuplicate: store.transactions.contains { $0.reconciliationFingerprint == fingerprint },
            validationError: nil
        )
        if let index = previewRows.firstIndex(where: { $0.id == row.id }) {
            previewRows[index] = repaired
        }
        repairingRow = nil
    }

    private func loadSampleCSV() {
        csvInputText = DaylightStore.sampleAustralianBankCSV(referenceDate: store.referenceDate)
        let detected = FinancialCalculationEngine.detectCSVColumnMapping(csvText: csvInputText)
        detectedHeaders = detected.headers
        mapping = detected.mapping
        refreshPreview()
    }

    private func refreshPreview() {
        let isCard = store.accounts.first(where: { $0.id == targetAccountId })?.accountType == .creditCard
        previewRows = FinancialCalculationEngine.previewCSVStatementImport(
            csvText: csvInputText,
            mapping: mapping,
            accountId: targetAccountId,
            isCreditCardAccount: isCard,
            existingTransactions: store.transactions,
            userMerchantRules: store.merchantRules,
            timeZoneId: store.profile.timeZoneId
        )
    }

    private func commitImport() {
        do {
            let key = FinancialCalculationEngine.makeStatementImportIdempotencyKey(
                accountId: targetAccountId,
                fileName: fileName,
                csvContent: csvInputText
            )
            completedJob = try store.commitCSVStatementImport(
                fileName: fileName,
                targetAccountId: targetAccountId,
                previewRows: previewRows,
                idempotencyKey: key
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
