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
                if tx.occurredAt < todayStart { return false }
            case .currentPeriod:
                if tx.occurredAt < store.allowanceSummary.periodStart { return false }
            case .last30Days:
                let thirtyAgo = cal.date(byAdding: .day, value: -30, to: todayStart) ?? todayStart
                if tx.occurredAt < thirtyAgo { return false }
            case .currentFY:
                if tx.occurredAt < fyBounds.start || tx.occurredAt > fyBounds.end { return false }
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
                filterControlsCard

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
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Search merchant, description, Opal, Woolworths...")
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

    // MARK: - Filter Controls Card

    private var filterControlsCard: some View {
        DaylightCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if let drilldown = store.transactionCategoryDrilldown {
                    HStack {
                        DaylightBadge("Drill-down: \(drilldown.displayName)", icon: drilldown.symbolName, tone: .neutral)
                        Spacer()
                        Button("Clear Drill-down") {
                            store.transactionCategoryDrilldown = nil
                        }
                        .font(.caption.weight(.semibold))
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

                        if selectedCategory != nil || selectedAccountId != nil || directionFilter != nil || dateRangeFilter != .all || !searchText.isEmpty {
                            Button("Reset") {
                                selectedCategory = nil
                                store.transactionCategoryDrilldown = nil
                                selectedAccountId = nil
                                directionFilter = nil
                                dateRangeFilter = .all
                                searchText = ""
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                let netOutflow = filteredTransactions
                    .filter { $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment }
                    .reduce(MoneyCents(0)) { $0 + $1.amountCents }
                let netInflow = filteredTransactions
                    .filter { $0.direction == .credit && $0.kind != .ownAccountTransfer }
                    .reduce(MoneyCents(0)) { $0 + $1.amountCents }

                HStack {
                    Text("\(filteredTransactions.count) matching transaction\(filteredTransactions.count == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Outflows: \(AustralianMoneyFormatter.format(cents: netOutflow)) • Inflows: \(AustralianMoneyFormatter.format(cents: netInflow))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bulkActionBanner: some View {
        DaylightCard(padding: 12) {
            HStack(spacing: 12) {
                Text("\(selectedIdsForBulk.count) selected")
                    .font(.subheadline.weight(.semibold))

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
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(DaylightTheme.accent)
                .disabled(selectedIdsForBulk.isEmpty)
            }
        }
    }

    // MARK: - Transactions List Card

    private var transactionsListCard: some View {
        DaylightCard {
            if filteredTransactions.isEmpty {
                DaylightEmptyState(
                    icon: "magnifyingglass",
                    title: "No transactions match your current filters",
                    message: "Try clearing a filter, importing a CSV bank statement, or adding a transaction manually.",
                    actionTitle: "Import CSV Statement"
                ) {
                    store.showingStatementImporter = true
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTransactions) { tx in
                        let accountName = store.accounts.first(where: { $0.id == tx.accountId })?.nickname ?? "Account"
                        HStack(spacing: 12) {
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
                            }

                            Button {
                                selectedTransactionForDetail = tx
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: tx.category.symbolName)
                                        .foregroundStyle(tx.category.tintColor)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(tx.category.tintColor.opacity(0.14)))

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(tx.merchantName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if tx.isRecurring {
                                                Image(systemName: "repeat.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(DaylightTheme.accent)
                                                    .help("Recurring payment")
                                            }
                                            if !tx.splits.isEmpty {
                                                DaylightBadge("Split (\(tx.splits.count))", icon: "arrow.triangle.branch", tone: .neutral)
                                            }
                                            if tx.classificationConfidence < 0.70 {
                                                DaylightBadge("Uncertain Category", icon: "questionmark.circle", tone: .warning)
                                            }
                                        }

                                        Text("\(tx.category.displayName) • \(accountName) • \(tx.paymentRail ?? tx.source.displayName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("\(AustralianDateHelper.formatDateTime(tx.occurredAt, timeZoneId: store.profile.timeZoneId)) • \(tx.status.displayName) • \(tx.source.displayName)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        if !tx.userNote.isEmpty {
                                            Text("Note: \(tx.userNote)")
                                                .font(.caption2)
                                                .foregroundStyle(DaylightTheme.accent)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(
                                            AustralianMoneyFormatter.format(
                                                cents: tx.direction == .debit ? -tx.amountCents : tx.amountCents,
                                                showPlusForPositive: true
                                            )
                                        )
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(tx.direction == .credit ? DaylightTheme.positive : .primary)

                                        Text(tx.kind.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        if tx.excludeFromBudget {
                                            Text("Excluded from budget")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(DaylightTheme.warning)
                                        }
                                    }
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                    }
                }
            }
        }
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
                        Picker("First Split Category", selection: $splitPart1Category) {
                            ForEach(AustralianCategory.allCases) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        Picker("Remaining Balance Category", selection: $splitPart2Category) {
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
        if !selectedCustomCategoryName.isEmpty && !userNote.contains("[\(selectedCustomCategoryName)]") {
            updated.userNote = userNote.isEmpty ? "[\(selectedCustomCategoryName)]" : "[\(selectedCustomCategoryName)] \(userNote)"
        } else {
            updated.userNote = userNote
        }
        updated.excludeFromBudget = excludeFromBudget
        updated.splits = splits

        do {
            try store.updateTransaction(updated, createMerchantRuleForFuture: saveMerchantRuleForFuture)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
                            let inferred = FinancialCalculationEngine.classifyAustralianTransaction(
                                rawDescription: newValue,
                                direction: direction,
                                isCreditCardAccount: false,
                                userMerchantRules: store.merchantRules
                            )
                            if inferred.confidence >= 0.85 {
                                category = inferred.category
                                kind = inferred.kind
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
                                        repairRejectedRow(row)
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

    private func repairRejectedRow(_ rejectedRow: ParsedCSVRowPreview) {
        let todayFormatted = AustralianDateHelper.formatISODate(store.referenceDate, timeZoneId: store.profile.timeZoneId)
        let cleanedDesc = rejectedRow.parsedDescription.isEmpty ? "REPAIRED STATEMENT ENTRY" : rejectedRow.parsedDescription
        let replacementLine = "\(todayFormatted),\(cleanedDesc),-15.00,2400.00"
        csvInputText = csvInputText.replacingOccurrences(of: rejectedRow.rawLine, with: replacementLine)
        refreshPreview()
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
            let key = "import:\(fileName):\(csvInputText.hashValue):\(Date().timeIntervalSince1970)"
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
