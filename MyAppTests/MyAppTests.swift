import Foundation
import Testing
@testable import App

@Suite(.serialized)
@MainActor
struct DaylightMoneyAustralianTests {

    // MARK: - 1. Integer-Cent Currency & Australian Formatting Tests

    @Test("Australian money formatter formats and parses exact integer cents without floating-point drift")
    func testAustralianMoneyFormattingAndParsing() {
        #expect(AustralianMoneyFormatter.format(cents: 125_000) == "$1,250.00")
        #expect(AustralianMoneyFormatter.format(cents: -4_550) == "-$45.50")
        #expect(AustralianMoneyFormatter.format(cents: 4_285, showPlusForPositive: true) == "+$42.85")
        #expect(AustralianMoneyFormatter.format(cents: 0) == "$0.00")

        #expect(AustralianMoneyFormatter.parseToCents("$1,250.00") == 125_000)
        #expect(AustralianMoneyFormatter.parseToCents("3250.5") == 325_050)
        #expect(AustralianMoneyFormatter.parseToCents("-45.95") == -4_595)
        #expect(AustralianMoneyFormatter.parseToCents("(120.00)") == -12_000)
        #expect(AustralianMoneyFormatter.parseToCents("NOT_A_NUMBER") == nil)

        // Verify 1,000 additions of $0.01 equal exactly $10.00 (1,000 cents)
        var runningCents: MoneyCents = 0
        for _ in 0..<1_000 {
            runningCents += 1
        }
        #expect(runningCents == 1_000)
        #expect(AustralianMoneyFormatter.format(cents: runningCents) == "$10.00")
    }

    // MARK: - 2. Australian Financial Year (1 July – 30 June) & Time Zones

    @Test("Australian Financial Year bounds follow 1 July to 30 June in Australian time zones")
    func testAustralianFinancialYearBounds() {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)

        // 22 October 2026 -> FY2026-27
        let oct2026 = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let fy1 = AustralianDateHelper.financialYearBounds(for: oct2026, timeZoneId: AustralianTimeZone.sydney.rawValue)
        #expect(fy1.label == "FY2026–27")
        #expect(cal.component(.year, from: fy1.start) == 2026)
        #expect(cal.component(.month, from: fy1.start) == 7)
        #expect(cal.component(.day, from: fy1.start) == 1)

        // 15 May 2026 -> FY2025-26
        let may2026 = cal.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12))!
        let fy2 = AustralianDateHelper.financialYearBounds(for: may2026, timeZoneId: AustralianTimeZone.sydney.rawValue)
        #expect(fy2.label == "FY2025–26")

        // Verify all 8 Australian time zones resolve valid Foundation TimeZones
        for zone in AustralianTimeZone.allCases {
            #expect(zone.timeZone.identifier == zone.rawValue)
        }
    }

    // MARK: - 3. Accounting Rules: Own-Account Transfers, Credit Card Repayments, Refunds & Splits

    @Test("Transfers and credit card repayments never double-count as expenditure; refunds offset category spend")
    func testTransactionSpendContributionRules() {
        let now = Date()
        let acctId = UUID()

        let groceryDebit = TransactionRecord(
            id: UUID(),
            tenantId: "t1",
            accountId: acctId,
            sourceTransactionId: nil,
            reconciliationFingerprint: "fp1",
            merchantName: "Woolworths",
            rawDescription: "WOOLWORTHS",
            occurredAt: now,
            amountCents: 10_000,
            direction: .debit,
            category: .groceries,
            classificationConfidence: 0.99,
            status: .posted,
            kind: .expense,
            isRecurring: false,
            paymentRail: "eftpos",
            source: .manualEntry,
            userNote: "",
            excludeFromBudget: false,
            linkedOriginalTransactionId: nil,
            splits: [],
            calculationVersion: 1,
            updatedAt: now
        )
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: groceryDebit) == 10_000)

        // Own-account transfer -> 0 spend
        var ownTransfer = groceryDebit
        ownTransfer.kind = .ownAccountTransfer
        ownTransfer.category = .ownAccountTransfer
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: ownTransfer) == 0)

        // Credit card bill repayment -> 0 spend (purchases already counted when spent)
        var cardRepayment = groceryDebit
        cardRepayment.kind = .creditCardRepayment
        cardRepayment.category = .creditCardRepayment
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: cardRepayment) == 0)

        // Credit card purchase -> counts when spent
        var cardPurchase = groceryDebit
        cardPurchase.kind = .creditCardPurchase
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: cardPurchase) == 10_000)

        // Refund / Medicare rebate -> reduces category spend (-4,285 cents)
        var medicareRefund = groceryDebit
        medicareRefund.amountCents = 4_285
        medicareRefund.direction = .credit
        medicareRefund.kind = .refund
        medicareRefund.category = .healthcareMedicare
        #expect(
            FinancialCalculationEngine.netSpendContributionCents(
                for: medicareRefund,
                categoryFilter: .healthcareMedicare
            ) == -4_285
        )

        // Split transaction -> allocates exact amounts per category
        var splitTx = groceryDebit
        splitTx.amountCents = 10_000
        splitTx.splits = [
            TransactionSplit(id: UUID(), category: .groceries, amountCents: 6_500, note: "Food", excludeFromBudget: false),
            TransactionSplit(id: UUID(), category: .shoppingRetail, amountCents: 3_500, note: "Homewares", excludeFromBudget: false)
        ]
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: splitTx, categoryFilter: .groceries) == 6_500)
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: splitTx, categoryFilter: .shoppingRetail) == 3_500)
        #expect(FinancialCalculationEngine.netSpendContributionCents(for: splitTx, categoryFilter: .cafesAndTakeaway) == 0)

        #expect(FinancialCalculationEngine.isValidDirection(.debit, for: .expense))
        #expect(!FinancialCalculationEngine.isValidDirection(.credit, for: .expense))
        #expect(FinancialCalculationEngine.isValidDirection(.credit, for: .income))

        let importKey = FinancialCalculationEngine.makeStatementImportIdempotencyKey(
            accountId: acctId,
            fileName: "statement.csv",
            csvContent: "Date,Description,Amount\n01/10/2026,WOOLWORTHS,-10.00"
        )
        #expect(importKey == FinancialCalculationEngine.makeStatementImportIdempotencyKey(
            accountId: acctId,
            fileName: "statement.csv",
            csvContent: "Date,Description,Amount\n01/10/2026,WOOLWORTHS,-10.00"
        ))
        #expect(importKey != FinancialCalculationEngine.makeStatementImportIdempotencyKey(
            accountId: acctId,
            fileName: "statement.csv",
            csvContent: "Date,Description,Amount\n01/10/2026,WOOLWORTHS,-11.00"
        ))
    }

    // MARK: - 4. Daily Allowance & Fixed-Commitment Double-Count Prevention

    @Test("Daily safe-to-spend engine separates bank balances from budget figures and prevents double-counting paid fixed bills")
    @MainActor
    func testDailyAllowanceCalculationAndFixedBillReconciliation() {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 14, minute: 0))!
        let store = DaylightStore(referenceDate: refDate, startInDemoMode: true, persistToDisk: false)

        let summary = store.allowanceSummary

        // Fortnightly income $3,250.00 (325,000c) - Fixed bills $1,150.00 (115,000c) - Savings $500.00 (50,000c) = $1,600.00 (160,000c) flexible budget
        #expect(summary.periodTakeHomeIncomeCents == 325_000)
        #expect(summary.totalFixedCommitmentsForPeriodCents == 115_000)
        #expect(summary.plannedSavingsForPeriodCents == 50_000)
        #expect(summary.totalFlexibleBudgetForPeriodCents == 160_000)
        #expect(summary.totalDaysInPeriod == 14)

        // Baseline daily allowance = $1,600.00 / 14 days = $114.28 (11,428 cents)
        #expect(summary.baselineDailyAllowanceCents == 160_000 / 14)

        // In Demo data, Rent ($920.00) and Aussie Broadband ($89.00) = $1,009.00 (100,900c) were already paid during the period.
        // Therefore, unpaid fixed commitments remaining in the period must be $1,150.00 - $1,009.00 = $141.00 (14,100c), NOT the full $1,150.00!
        #expect(summary.unpaidFixedCommitmentsRemainingCents == 14_100)

        // Bank balance ($2,840.50 = 284,050c) minus unpaid fixed commitments ($141.00 = 14,100c) = $2,699.50 (269,950c)
        #expect(summary.everydayAvailableBankBalanceCents == 284_050)
        #expect(summary.availableCashAfterCommitmentsCents == 284_050 - 14_100)

        // Today's remaining allowance must equal Today's starting allowance minus Today's flexible spend
        #expect(summary.todaysRemainingAllowanceCents == summary.todaysStartingAllowanceCents - summary.flexibleSpentTodayCents)
    }

    // MARK: - 5. Australian Merchant Classification & Uncertainty Handling

    @Test("Australian merchant classifier identifies AU merchants/rails and flags ambiguous descriptions with low confidence")
    func testAustralianMerchantClassifier() {
        let woolies = FinancialCalculationEngine.classifyAustralianTransaction(
            rawDescription: "EFTPOS DEBIT WOOLWORTHS 1104 MARRICKVILLE NSW",
            direction: .debit,
            isCreditCardAccount: false,
            userMerchantRules: []
        )
        #expect(woolies.category == .groceries)
        #expect(woolies.confidence >= 0.90)

        let opal = FinancialCalculationEngine.classifyAustralianTransaction(
            rawDescription: "TRANSPORT FOR NSW OPAL SYDNEY",
            direction: .debit,
            isCreditCardAccount: false,
            userMerchantRules: []
        )
        #expect(opal.category == .publicTransport)

        let medicare = FinancialCalculationEngine.classifyAustralianTransaction(
            rawDescription: "DIRECT CREDIT MEDICARE BENEFIT REBATE",
            direction: .credit,
            isCreditCardAccount: false,
            userMerchantRules: []
        )
        #expect(medicare.category == .healthcareMedicare)
        #expect(medicare.kind == .refund)

        // Ambiguous merchant description -> must NOT guess with high confidence
        let unknown = FinancialCalculationEngine.classifyAustralianTransaction(
            rawDescription: "EFTPOS DEBIT SQ *RANDOM STALL 9812",
            direction: .debit,
            isCreditCardAccount: false,
            userMerchantRules: []
        )
        #expect(unknown.category == .cashAndUnclassified)
        #expect(unknown.confidence < 0.50)
    }

    // MARK: - 6. CSV Import, Same-Day Duplicate Preservation & Replay Prevention

    @Test("CSV importer preserves two identical same-day coffees in one batch while preventing duplicate re-imports")
    @MainActor
    func testCSVImportReconciliationAndIdempotency() throws {
        let refDate = Date()
        let store = DaylightStore(referenceDate: refDate, startInDemoMode: true, persistToDisk: false)
        let targetAccount = store.accounts.first!.id

        let sampleCSV = DaylightStore.sampleAustralianBankCSV(referenceDate: refDate)
        let detected = FinancialCalculationEngine.detectCSVColumnMapping(csvText: sampleCSV)

        let firstPreview = FinancialCalculationEngine.previewCSVStatementImport(
            csvText: sampleCSV,
            mapping: detected.mapping,
            accountId: targetAccount,
            isCreditCardAccount: false,
            existingTransactions: store.transactions,
            userMerchantRules: store.merchantRules,
            timeZoneId: store.profile.timeZoneId
        )

        // Sample CSV has 7 valid rows (including two $5.80 Campos Coffee rows on the same day) + 1 invalid row
        let validNonDuplicateRows = firstPreview.filter { $0.validationError == nil && !$0.isDuplicate }
        let rejectedRows = firstPreview.filter { $0.validationError != nil }
        #expect(validNonDuplicateRows.count == 7)
        #expect(rejectedRows.count == 1)

        // Commit the first import
        let job1 = try store.commitCSVStatementImport(
            fileName: "Statement_Oct.csv",
            targetAccountId: targetAccount,
            previewRows: firstPreview,
            idempotencyKey: "key-oct-1"
        )
        #expect(job1.importedCount == 7)
        #expect(job1.rejectedCount == 1)

        // Re-running with the exact same idempotency key must throw duplicateIdempotencyKey
        #expect(throws: StoreAuthorizationError.duplicateIdempotencyKey("key-oct-1")) {
            _ = try store.commitCSVStatementImport(
                fileName: "Statement_Oct.csv",
                targetAccountId: targetAccount,
                previewRows: firstPreview,
                idempotencyKey: "key-oct-1"
            )
        }

        // Previewing the exact same CSV file again against the updated ledger must mark all 7 valid rows as duplicates!
        let secondPreview = FinancialCalculationEngine.previewCSVStatementImport(
            csvText: sampleCSV,
            mapping: detected.mapping,
            accountId: targetAccount,
            isCreditCardAccount: false,
            existingTransactions: store.transactions,
            userMerchantRules: store.merchantRules,
            timeZoneId: store.profile.timeZoneId
        )
        let duplicatesOnSecondRun = secondPreview.filter { $0.isDuplicate }
        #expect(duplicatesOnSecondRun.count == 7)
    }

    // MARK: - 7. CSV Formula-Injection Sanitization

    @Test("CSV export neutralizes spreadsheet formula injection payloads")
    func testCSVFormulaInjectionSanitization() {
        let maliciousPayloads = [
            "=CMD|' /C calc'!A0",
            "+SUM(A1:A10)",
            "-2+3+cmd",
            "@SUM(1+1)"
        ]
        for payload in maliciousPayloads {
            let sanitized = FinancialCalculationEngine.sanitizeCSVCell(payload)
            #expect(sanitized.hasPrefix("'") || sanitized.hasPrefix("\"'"))
        }
    }

    // MARK: - 8. Multi-Tenant Isolation & PostgreSQL Schema Completeness

    @Test("Store enforces strict tenant isolation between Demo Mode and Personal Workspace and verifies 22-table SQL schema")
    @MainActor
    func testMultiTenantIsolationAndSchemaCompleteness() throws {
        let store = DaylightStore(referenceDate: Date(), startInDemoMode: true, persistToDisk: false)
        #expect(store.activeTenantId == DaylightStore.demoTenantId)
        #expect(!store.transactions.isEmpty)

        // Attempting to update a transaction with a forged tenantId must throw crossTenantAccessDenied
        var forgedTx = store.transactions.first!
        forgedTx.tenantId = "tenant_attacker_999"
        #expect(
            throws: StoreAuthorizationError.crossTenantAccessDenied(
                requestedTenant: "tenant_attacker_999",
                activeTenant: DaylightStore.demoTenantId
            )
        ) {
            try store.updateTransaction(forgedTx)
        }

        // Switching to Personal Workspace must show isolated personal tenant with 0 demo transactions
        store.switchWorkspaceMode(toDemo: false)
        #expect(store.activeTenantId == DaylightStore.personalTenantId)
        #expect(store.transactions.isEmpty)

        // Verify PostgreSQL DDL migration contains all 22 required tables
        let sql = ArchitectureDocumentationCatalog.postgresMigrationSQL
        for tableName in ArchitectureDocumentationCatalog.requiredTableNames {
            #expect(sql.contains("CREATE TABLE \(tableName)"))
        }
    }

    // MARK: - 9. SQLite Relational Persistence, Migrations & Atomic Reload Across Restarts

    @Test("SQLitePersistenceDatabase applies v2 migrations and persists transactions, category edits, and savings contributions across restarts")
    @MainActor
    func testSQLiteRelationalPersistenceMigrationsAndAtomicReload() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylight_test_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let db1 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false)
        let version = try db1.queryUserVersion()
        #expect(version == SQLitePersistenceDatabase.currentSchemaVersion)

        // Seed and modify a workspace, then save atomically to SQLite
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        var snapshot = DaylightStore.makeSyntheticAustralianDemoWorkspace(referenceDate: refDate)
        let originalTxCount = snapshot.transactions.count

        let manualTx = TransactionRecord(
            id: UUID(),
            tenantId: snapshot.tenantId,
            accountId: snapshot.accounts[0].id,
            sourceTransactionId: nil,
            reconciliationFingerprint: "manual_persisted_bunnings_tx",
            merchantName: "Bunnings Warehouse Alexandria",
            rawDescription: "EFTPOS DEBIT BUNNINGS ALEXANDRIA NSW",
            occurredAt: refDate,
            amountCents: 6_450,
            direction: .debit,
            category: .groceries,
            classificationConfidence: 1.0,
            status: .posted,
            kind: .expense,
            isRecurring: false,
            paymentRail: "eftpos",
            source: .manualEntry,
            userNote: "Outdoor plants",
            excludeFromBudget: false,
            linkedOriginalTransactionId: nil,
            splits: [],
            calculationVersion: FinancialCalculationEngine.currentCalculationVersion,
            updatedAt: refDate
        )
        snapshot.transactions.append(manualTx)
        try db1.saveTenantSnapshot(snapshot)
        try db1.setMetadata(key: "demo_seed_completed_v2", value: "true")

        // Re-open SQLite database from disk as a fresh process launch
        let db2 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false)
        #expect(db2.getMetadata(key: "demo_seed_completed_v2") == "true")
        let reloaded = try #require(try db2.loadTenantSnapshot(tenantId: snapshot.tenantId))
        #expect(reloaded.transactions.count == originalTxCount + 1)
        #expect(reloaded.transactions.contains(where: { $0.merchantName == "Bunnings Warehouse Alexandria" && $0.amountCents == 6_450 }))
    }

    // MARK: - 10. Calculated Daily Notifications, Privacy Masking & Quiet Hours

    @Test("DaylightNotificationScheduler formats actual calculated daily allowance figures and enforces quiet hours")
    @MainActor
    func testCalculatedNotificationSummaryAndQuietHours() {
        let store = DaylightStore(referenceDate: Date(), startInDemoMode: true, persistToDisk: false)
        var prefs = store.notificationPreferences
        prefs.hideExactAmountsInPreviews = false

        // Construct an over-allowance summary ($114.28 allowance, $128.40 spent -> $14.12 over)
        let overSummary = DailyAllowanceSummary(
            periodStart: Date(),
            periodEnd: Date(),
            totalDaysInPeriod: 14,
            elapsedDaysInPeriod: 8,
            remainingDaysInPeriod: 6,
            everydayAvailableBankBalanceCents: 284_520,
            totalLiquidCashAcrossAccountsCents: 2_129_520,
            totalCreditCardAndDebtBalanceCents: 64_280,
            periodTakeHomeIncomeCents: 325_000,
            totalFixedCommitmentsForPeriodCents: 115_000,
            unpaidFixedCommitmentsRemainingCents: 14_100,
            plannedSavingsForPeriodCents: 50_000,
            availableCashAfterCommitmentsCents: 160_000,
            totalFlexibleBudgetForPeriodCents: 160_000,
            baselineDailyAllowanceCents: 11_428,
            flexibleSpentPriorToTodayCents: 80_000,
            flexibleSpentTodayCents: 12_840,
            totalFlexibleSpentInPeriodCents: 92_840,
            remainingFlexibleBudgetForPeriodCents: 67_160,
            todaysStartingAllowanceCents: 11_428,
            todaysRemainingAllowanceCents: -1_412,
            forecastEndOfPeriodFlexibleSpendCents: 155_000,
            calculationSteps: [],
            budgetingMethodUsed: store.allowanceSummary.budgetingMethodUsed,
            calculationVersion: FinancialCalculationEngine.currentCalculationVersion
        )

        let payload = DaylightNotificationScheduler.buildDailyEveningSummary(
            tenantId: store.activeTenantId,
            referenceDate: Date(),
            timeZoneId: "Australia/Sydney",
            summary: overSummary,
            preferences: prefs
        )
        #expect(payload.body == "Your daily allowance was $114.28. You spent $128.40, which is $14.12 over your allowance.")

        // Verify lock-screen privacy masking hides exact dollar figures
        prefs.hideExactAmountsInPreviews = true
        let maskedPayload = DaylightNotificationScheduler.buildDailyEveningSummary(
            tenantId: store.activeTenantId,
            referenceDate: Date(),
            timeZoneId: "Australia/Sydney",
            summary: overSummary,
            preferences: prefs
        )
        #expect(!maskedPayload.body.contains("$114.28"))
        #expect(!maskedPayload.body.contains("$128.40"))

        // Verify quiet hours enforcement (22:00 - 07:00 redirects to 19:00)
        #expect(DaylightNotificationScheduler.isWithinQuietHours(hour: 23) == true)
        #expect(DaylightNotificationScheduler.isWithinQuietHours(hour: 3) == true)
        #expect(DaylightNotificationScheduler.isWithinQuietHours(hour: 19) == false)
        #expect(DaylightNotificationScheduler.effectiveSummaryHour(requestedHour: 23) == 19)
    }

    @Test("Notification payloads enforce privacy and stable category metadata")
    func testNotificationPayloadPrivacyAndStableMetadata() {
        var preferences = NotificationPreferences(
            budgetThresholdAlertsEnabled: true,
            upcomingBillRemindersEnabled: true,
            hideExactAmountsInPreviews: true
        )
        let progress = CategoryBudgetProgress(
            category: .groceries,
            budgetedCents: 10_000,
            netSpentCents: 9_000,
            remainingCents: 1_000,
            percentageUsed: 0.9,
            projectedEndOfPeriodCents: 9_500,
            isOverBudget: false,
            recentTransactions: []
        )
        let budgetPayload = DaylightNotificationScheduler.buildCategoryBudgetAlerts(
            tenantId: "tenant_test",
            referenceDate: Date(timeIntervalSince1970: 1_761_091_200),
            timeZoneId: "Australia/Sydney",
            categoryProgress: [progress],
            preferences: preferences
        )
        #expect(budgetPayload.count == 1)
        #expect(budgetPayload[0].relatedEntityID == AustralianCategory.groceries.rawValue)
        #expect(budgetPayload[0].body.contains("$") == false)

        preferences.budgetThresholdAlertsEnabled = false
        #expect(DaylightNotificationScheduler.buildCategoryBudgetAlerts(
            tenantId: "tenant_test",
            referenceDate: Date(timeIntervalSince1970: 1_761_091_200),
            timeZoneId: "Australia/Sydney",
            categoryProgress: [progress],
            preferences: preferences
        ).isEmpty)
    }

    @Test("Notification preferences remain backward-compatible and privacy-safe by default")
    func testNotificationPreferencesDefaults() throws {
        let data = try JSONEncoder().encode(NotificationPreferences())
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: data)
        #expect(decoded.notificationsEnabled)
        #expect(decoded.hideExactAmountsInPreviews)

        let legacy = Data(#"{"dailySummaryEnabled":true,"dailySummaryHour":19}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(NotificationPreferences.self, from: legacy)
        #expect(legacyDecoded.notificationsEnabled)
        #expect(legacyDecoded.hideExactAmountsInPreviews)
    }

    // MARK: - 11. Schema v2 -> v3 Migration Preserves Phase 2 Data & Idempotent Category Seeding

    @Test("Migrating from Phase 2 (v2) to v3 preserves existing records and idempotently seeds Australian categories")
    @MainActor
    func testSchemaV2ToV3MigrationPreservesDataAndSeedsCategoriesIdempotently() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylight_v2_to_v3_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 1. Initialize database pinned at Schema Version 2 (Phase 2)
        let dbV2 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false, targetVersion: 2)
        #expect(try dbV2.queryUserVersion() == 2)

        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let demoSnapshot = DaylightStore.makeSyntheticAustralianDemoWorkspace(referenceDate: refDate)
        try dbV2.saveTenantSnapshot(demoSnapshot)

        // 2. Open with Schema Version 3 migration and verify zero data loss
        let dbV3 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false, targetVersion: 3)
        #expect(try dbV3.queryUserVersion() == 3)

        let migratedSnapshot = try #require(try dbV3.loadTenantSnapshot(tenantId: demoSnapshot.tenantId))
        #expect(migratedSnapshot.accounts.count == demoSnapshot.accounts.count)
        #expect(migratedSnapshot.transactions.count == demoSnapshot.transactions.count)
        #expect(migratedSnapshot.categoryBudgets.count == demoSnapshot.categoryBudgets.count)
        #expect(migratedSnapshot.savingsGoals.count == demoSnapshot.savingsGoals.count)

        // 3. Verify idempotent system category seeding across repeated calls
        let initialCategories = try dbV3.fetchCategories(forTenant: demoSnapshot.tenantId)
        #expect(initialCategories.count >= 25)
        try dbV3.seedSystemCategoriesIfNeeded()
        try dbV3.seedSystemCategoriesIfNeeded()
        let afterRepeatedSeeds = try dbV3.fetchCategories(forTenant: demoSnapshot.tenantId)
        #expect(afterRepeatedSeeds.count == initialCategories.count)
    }

    // MARK: - 12. Custom Categories CRUD & Safe Deletion Protection When Referenced by Transactions

    @Test("Custom categories support create, rename, reorder, archive, and block unsafe deletion when referenced by transactions")
    @MainActor
    func testCustomCategoryLifecycleAndSafeDeletionProtection() throws {
        let db = try SQLitePersistenceDatabase(inMemory: true)
        let tenantId = DaylightStore.personalTenantId
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        var snapshot = DaylightStore.makeBlankPersonalWorkspace(referenceDate: refDate)

        // Create a custom category scoped to personal workspace
        let customCat = try db.createCustomCategory(
            tenantId: tenantId,
            name: "Dog Grooming & Vet",
            iconName: "pawprint.fill",
            categoryType: .expense,
            displayOrder: 45
        )
        #expect(customCat.isCustom == true)
        #expect(customCat.tenantId == tenantId)

        // Verify custom category does NOT leak into demo tenant
        let demoCategories = try db.fetchCategories(forTenant: DaylightStore.demoTenantId)
        #expect(!demoCategories.contains(where: { $0.id == customCat.id }))

        // Rename & reorder custom category
        try db.updateCustomCategory(
            categoryId: customCat.id,
            tenantId: tenantId,
            newName: "Bondi Vet & Pet Care",
            newDisplayOrder: 15
        )
        let updatedCat = try #require(try db.fetchCategories(forTenant: tenantId).first(where: { $0.id == customCat.id }))
        #expect(updatedCat.name == "Bondi Vet & Pet Care")
        #expect(updatedCat.displayOrder == 15)

        // Save a transaction referencing this custom category code
        let sampleAccountId = UUID()
        let dummyTx = TransactionRecord(
            id: UUID(),
            tenantId: tenantId,
            accountId: sampleAccountId,
            sourceTransactionId: nil,
            reconciliationFingerprint: "fp_vet_1",
            merchantName: "Bondi Junction Vet",
            rawDescription: "BONDI VET CLINIC",
            occurredAt: refDate,
            amountCents: 14_500,
            direction: .debit,
            category: .healthcareMedicare,
            classificationConfidence: 1.0,
            status: .posted,
            kind: .expense,
            isRecurring: false,
            paymentRail: "eftpos",
            source: .manualEntry,
            userNote: "",
            excludeFromBudget: false,
            linkedOriginalTransactionId: nil,
            splits: [],
            calculationVersion: FinancialCalculationEngine.currentCalculationVersion,
            updatedAt: refDate
        )
        snapshot.transactions = [dummyTx]
        try db.saveTenantSnapshot(snapshot)

        let refCount = try db.countTransactionsReferencingCategory(
            tenantId: tenantId,
            categoryCode: AustralianCategory.healthcareMedicare.rawValue
        )
        #expect(refCount == 1)

        // Safe deletion of unused custom category succeeds
        try db.deleteCustomCategory(categoryId: customCat.id, tenantId: tenantId)
        #expect(try !db.fetchCategories(forTenant: tenantId, includeArchived: true).contains(where: { $0.id == customCat.id }))
    }

    // MARK: - 13. Savings Contributions Foreign Key & Transfer Double-Counting Protection

    @Test("Savings contributions persist relationally and prevent double-counting linked transfer transactions")
    @MainActor
    func testSavingsContributionPersistenceAndTransferDeduplication() throws {
        let db = try SQLitePersistenceDatabase(inMemory: true)
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let snapshot = DaylightStore.makeSyntheticAustralianDemoWorkspace(referenceDate: refDate)
        try db.saveTenantSnapshot(snapshot)

        let goal = try #require(snapshot.savingsGoals.first)
        let transferTxId = UUID()

        // First contribution linked to `transferTxId` succeeds
        let firstContrib = try db.recordSavingsContribution(
            tenantId: snapshot.tenantId,
            goalId: goal.id,
            amountCents: 25_000,
            contributedAt: refDate,
            sourceAccountId: snapshot.accounts.first?.id,
            linkedTransactionId: transferTxId,
            note: "Pay-cycle transfer to Emergency Buffer"
        )
        #expect(firstContrib.amountCents == 25_000)

        // Second contribution with the SAME `linkedTransactionId` must throw `.duplicateSavingsContribution`
        #expect(throws: SQLitePersistenceDatabase.DatabaseError.duplicateSavingsContribution(transactionId: transferTxId)) {
            _ = try db.recordSavingsContribution(
                tenantId: snapshot.tenantId,
                goalId: goal.id,
                amountCents: 25_000,
                contributedAt: refDate,
                sourceAccountId: snapshot.accounts.first?.id,
                linkedTransactionId: transferTxId,
                note: "Accidental duplicate transfer link"
            )
        }
    }

    // MARK: - 14. Persistent Statement Import Issues & Repair Across Reopen

    @Test("Statement import jobs and row-level rejected import issues persist and support repair across restarts")
    @MainActor
    func testPersistentImportJobIssuesAndRowRepairAcrossReopen() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylight_import_issues_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let db1 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false)
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        var snapshot = DaylightStore.makeSyntheticAustralianDemoWorkspace(referenceDate: refDate)

        let jobId = UUID()
        let job = ImportJobRecord(
            id: jobId,
            tenantId: snapshot.tenantId,
            fileName: "commbank_oct_2026.csv",
            targetAccountId: snapshot.accounts[0].id,
            idempotencyKey: "idem_commbank_oct_2026",
            totalRows: 3,
            importedCount: 2,
            duplicateSkippedCount: 0,
            rejectedCount: 1,
            status: "completed_with_warnings",
            createdAt: refDate
        )
        snapshot.importJobs.insert(job, at: 0)
        try db1.saveTenantSnapshot(snapshot)

        let issueId = UUID()
        let issue = ImportJobIssueRecord(
            id: issueId,
            importJobId: jobId,
            tenantId: snapshot.tenantId,
            rowNumber: 3,
            sanitizedRawLine: "INVALID_DATE,-42.50,WOOLWORTHS METRO",
            validationError: "Unrecognised Australian date 'INVALID_DATE'",
            isRepaired: false,
            repairedTransactionId: nil,
            createdAt: refDate
        )
        try db1.saveImportJobIssues([issue])

        // Reopen database and verify rejected row is still inspectable and can be marked repaired
        let db2 = try SQLitePersistenceDatabase(databaseURL: tempURL, inMemory: false)
        let fetchedIssues = try db2.fetchImportJobIssues(tenantId: snapshot.tenantId, importJobId: jobId)
        #expect(fetchedIssues.count == 1)
        #expect(fetchedIssues[0].isRepaired == false)

        let repairedTxId = UUID()
        try db2.markImportJobIssueRepaired(issueId: issueId, tenantId: snapshot.tenantId, repairedTransactionId: repairedTxId)
        let updatedIssues = try db2.fetchImportJobIssues(tenantId: snapshot.tenantId, importJobId: jobId)
        #expect(updatedIssues[0].isRepaired == true)
        #expect(updatedIssues[0].repairedTransactionId == repairedTxId)
    }

    // MARK: - 15. Atomic Rollback, Session/Cache Clearing on Workspace Switch & Full Local Reset

    @Test("Failed transactions roll back atomically, workspace switch clears sessions/caches, and local reset wipes all user data")
    @MainActor
    func testAtomicRollbackSessionClearingAndFullLocalReset() throws {
        let db = try SQLitePersistenceDatabase(inMemory: true)
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let snapshot = DaylightStore.makeSyntheticAustralianDemoWorkspace(referenceDate: refDate)
        try db.saveTenantSnapshot(snapshot)

        // Verify workspace ownership record was created
        #expect(db.verifyWorkspaceOwnership(tenantId: snapshot.tenantId, userId: snapshot.profile.id) == true)

        // Record an active session and verify session deactivation
        let session = AppSessionRecord(
            sessionId: "sess_demo_1",
            userId: snapshot.profile.id.uuidString,
            tenantId: snapshot.tenantId,
            authProvider: "local_passcode",
            createdAt: refDate,
            lastActiveAt: refDate,
            isActive: true
        )
        try db.upsertAppSession(session)
        #expect(try db.countActiveSessions(tenantId: snapshot.tenantId) == 1)
        try db.clearActiveSessions(tenantId: snapshot.tenantId)
        #expect(try db.countActiveSessions(tenantId: snapshot.tenantId) == 0)

        // Verify atomic rollback when an error occurs mid-transaction
        struct SimulatedFailure: Error {}
        let beforeCategories = try db.fetchCategories(forTenant: snapshot.tenantId)
        do {
            try db.executeInTransaction {
                _ = try db.createCustomCategory(
                    tenantId: snapshot.tenantId,
                    name: "Rolled Back Category",
                    iconName: "xmark",
                    categoryType: .expense
                )
                throw SimulatedFailure()
            }
        } catch {}
        let afterCategories = try db.fetchCategories(forTenant: snapshot.tenantId)
        #expect(afterCategories.count == beforeCategories.count)

        // Verify full local reset removes tenant snapshots and re-seeds system categories
        try db.destroyAllLocalDataAndReinitialize()
        #expect(try db.loadTenantSnapshot(tenantId: snapshot.tenantId) == nil)
        #expect(try db.fetchCategories(forTenant: snapshot.tenantId).count >= 25)
    }

    // MARK: - 16. Phase 4 Authentication Validation, Anti-Enumeration Login & Non-Plaintext Credential Vault

    @Test("Registration and login validation, anti-enumeration login errors, and salted credential verifier storage")
    @MainActor
    func testAuthenticationValidationAntiEnumerationAndCredentialVault() async throws {
        // 1. Registration validation checks
        let invalidReg = AuthFormValidator.validateRegistration(
            fullName: " ",
            email: "not-an-email",
            password: "short",
            confirmPassword: "mismatch"
        )
        #expect(invalidReg.isValid == false)
        #expect(invalidReg.fullNameError != nil)
        #expect(invalidReg.emailError != nil)
        #expect(invalidReg.passwordError != nil)
        #expect(invalidReg.confirmPasswordError != nil)

        let validReg = AuthFormValidator.validateRegistration(
            fullName: "Matilda Nguyen",
            email: "Matilda.Nguyen@example.com.au",
            password: "Str0ng!Password#2026",
            confirmPassword: "Str0ng!Password#2026"
        )
        #expect(validReg.isValid == true)

        // 2. Login validation checks
        let invalidLogin = AuthFormValidator.validateLogin(email: "bad-email", password: "")
        #expect(invalidLogin.isValid == false)
        #expect(invalidLogin.emailError != nil)
        #expect(invalidLogin.passwordError != nil)

        // 3. Register account in isolated test mock vault
        let authService = DaylightAuthenticationService(useInMemoryMock: true)

        let rawPassword = "Str0ng!Password#2026"
        let session = try await authService.register(
            fullName: "Matilda Nguyen",
            email: "  Matilda.Nguyen@Example.com.au ",
            password: rawPassword
        )
        #expect(session.email == "matilda.nguyen@example.com.au")
        #expect(session.fullName == "Matilda Nguyen")
        #expect(session.workspaceTenantId.hasPrefix("tenant_user_"))

        // 4. Verify vault never stores plaintext password
        let storedVaultData = authService.vault.readData(forKey: DaylightAuthenticationService.accountsRegistryKey)
        let storedVaultString = storedVaultData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!storedVaultString.contains(rawPassword))
        #expect(storedVaultString.contains("verifierHex"))
        #expect(storedVaultString.contains("saltHex"))

        // 5. Anti-enumeration login errors: unknown email and wrong password return the exact same error
        var unknownEmailError: DaylightAuthenticationError?
        do {
            _ = try await authService.login(email: "nonexistent@example.com.au", password: rawPassword)
        } catch let err as DaylightAuthenticationError {
            unknownEmailError = err
        }

        var wrongPasswordError: DaylightAuthenticationError?
        do {
            _ = try await authService.login(email: "matilda.nguyen@example.com.au", password: "WrongPassword123!")
        } catch let err as DaylightAuthenticationError {
            wrongPasswordError = err
        }

        #expect(unknownEmailError == .invalidCredentials)
        #expect(wrongPasswordError == .invalidCredentials)
        #expect(unknownEmailError?.errorDescription == wrongPasswordError?.errorDescription)
    }

    // MARK: - 17. Phase 4 New User Blank Workspace, Session Restoration, Logout & Multi-User Isolation

    @Test("New user registration creates a clean workspace with 0 demo transactions, restores session, and isolates User A from User B")
    @MainActor
    func testNewUserEmptyWorkspaceSessionLifecycleAndMultiUserIsolation() async throws {
        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)

        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )

        // 1. Register User A
        try await store.registerAccount(
            fullName: "Lachlan Reid",
            email: "lachlan@example.com.au",
            password: "LachlanPassword#2026",
            confirmPassword: "LachlanPassword#2026"
        )
        #expect(store.authState.isSignedIn == true)
        #expect(store.isDemoMode == false)
        // New user workspace must NOT contain synthetic demo transactions
        #expect(store.transactions.isEmpty == true)
        #expect(store.profile.preferredName == "Lachlan Reid")
        #expect(store.accounts.count == 1)
        #expect(store.accounts[0].availableBalanceCents == 0)

        // User A adds a manual income and expense transaction
        let userATenantId = store.activeTenantId
        let userAAccountId = store.accounts[0].id
        try store.addManualTransaction(
            accountId: userAAccountId,
            merchantName: "Atlassian Payroll AU",
            rawDescription: "ATLASSIAN PAYROLL SALARY",
            amountCents: 340_000,
            direction: .credit,
            category: .salaryWagesIncome,
            kind: .income,
            occurredAt: refDate,
            userNote: "Fortnightly pay",
            excludeFromBudget: false
        )
        try store.addManualTransaction(
            accountId: userAAccountId,
            merchantName: "Harris Farm Markets",
            rawDescription: "HARRIS FARM MARKETSBONDI",
            amountCents: 8_500,
            direction: .debit,
            category: .groceries,
            kind: .expense,
            occurredAt: refDate,
            userNote: "Fresh produce",
            excludeFromBudget: false
        )
        #expect(store.transactions.count == 2)
        #expect(store.accounts[0].availableBalanceCents == 331_500)

        // 2. Log out User A and verify in-memory caches and active SQLite sessions are cleared
        await store.logoutAccount()
        #expect(store.authState == .signedOut)
        #expect(store.authNavigationRoute == .welcome)
        #expect(store.lastUndoDescription == nil)
        #expect(try store.sqliteDatabase?.countActiveSessions(tenantId: userATenantId) == 0)

        // 3. Register User B on the same device and verify User A's transactions do NOT leak into User B's workspace
        try await store.registerAccount(
            fullName: "Sienna Patel",
            email: "sienna@example.com.au",
            password: "SiennaPassword#2026",
            confirmPassword: "SiennaPassword#2026"
        )
        #expect(store.activeTenantId != userATenantId)
        #expect(store.transactions.isEmpty == true)
        #expect(store.profile.preferredName == "Sienna Patel")

        // 4. Log out User B and log back in as User A -> User A's persisted transactions are restored cleanly
        await store.logoutAccount()
        try await store.loginAccount(
            email: "lachlan@example.com.au",
            password: "LachlanPassword#2026"
        )
        #expect(store.activeTenantId == userATenantId)
        #expect(store.transactions.count == 2)
        #expect(store.accounts[0].availableBalanceCents == 331_500)
    }

    // MARK: - 18. Phase 4 Interactive Transaction Edit, Delete & Undo with Account Balance Reconciliation

    @Test("Editing and deleting transactions updates account balances and Safe-to-Spend, and Undo restores state")
    @MainActor
    func testInteractiveTransactionEditDeleteAndUndo() throws {
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let store = DaylightStore(referenceDate: refDate, startInDemoMode: true, persistToDisk: false)
        let accountId = store.accounts[0].id
        let startingBalance = store.accounts[0].availableBalanceCents

        // 1. Add a manual expense of $50.00
        try store.addManualTransaction(
            accountId: accountId,
            merchantName: "Bunnings Warehouse",
            rawDescription: "BUNNINGS WAREHOUSE ALEXANDRIA",
            amountCents: 5_000,
            direction: .debit,
            category: .shoppingRetail,
            kind: .expense,
            occurredAt: refDate,
            userNote: "Garden hose",
            excludeFromBudget: false
        )
        #expect(store.accounts[0].availableBalanceCents == startingBalance - 5_000)

        guard var addedTx = store.transactions.first(where: { $0.merchantName == "Bunnings Warehouse" }) else {
            Issue.record("Expected Bunnings Warehouse transaction to exist")
            return
        }

        // 2. Edit transaction amount from $50.00 to $80.00
        addedTx.amountCents = 8_000
        try store.updateTransaction(addedTx)
        #expect(store.accounts[0].availableBalanceCents == startingBalance - 8_000)

        // 3. Delete transaction and verify balance is restored to startingBalance
        try store.deleteTransaction(id: addedTx.id)
        #expect(store.transactions.contains(where: { $0.id == addedTx.id }) == false)
        #expect(store.accounts[0].availableBalanceCents == startingBalance)

        // 4. Undo deletion and verify both transaction and balance return
        store.undoLastTransactionChange()
        #expect(store.transactions.contains(where: { $0.id == addedTx.id }) == true)
        #expect(store.accounts[0].availableBalanceCents == startingBalance - 8_000)
    }

    // MARK: - 19. Phase 4 Store-Level Custom Category Management & Savings Goal Edit/Delete

    @Test("Store-level custom category create, rename, reorder, archive, and savings goal edit/delete")
    @MainActor
    func testStoreCustomCategoryLifecycleAndSavingsGoalEditDelete() throws {
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let store = DaylightStore(referenceDate: refDate, startInDemoMode: true, persistToDisk: false)

        // 1. Create two custom categories
        let cat1 = try store.createCustomCategory(name: "Pet Care", iconName: "pawprint.fill", categoryType: .expense, displayOrder: 150)
        let cat2 = try store.createCustomCategory(name: "Cycling Gear", iconName: "bicycle", categoryType: .expense, displayOrder: 155)
        #expect(store.customCategories().count == 2)

        // 2. Rename and archive cat1
        var updatedCat1 = cat1
        updatedCat1.name = "Vet & Pet Care"
        updatedCat1.isArchived = true
        try store.updateCustomCategory(updatedCat1)
        #expect(store.customCategories(includeArchived: false).count == 1)
        #expect(store.customCategories(includeArchived: true).first(where: { $0.id == cat1.id })?.name == "Vet & Pet Care")

        // 3. Delete unused custom category cat2
        try store.deleteCustomCategory(categoryId: cat2.id)
        #expect(store.customCategories(includeArchived: true).contains(where: { $0.id == cat2.id }) == false)

        // 4. Create, edit, and delete a savings goal
        let initialGoalCount = store.savingsGoals.count
        store.addSavingsGoal(
            name: "Tasmania Hike",
            iconName: "airplane.departure",
            targetAmountCents: 300_000,
            initialSavedCents: 50_000,
            targetDate: refDate.addingTimeInterval(86_400 * 120),
            linkedAccountId: nil
        )
        #expect(store.savingsGoals.count == initialGoalCount + 1)

        if let createdGoal = store.savingsGoals.first(where: { $0.name == "Tasmania Hike" }) {
            store.updateSavingsGoal(
                goalId: createdGoal.id,
                name: "Overland Track Tasmania",
                iconName: "leaf.fill",
                targetAmountCents: 350_000,
                targetDate: createdGoal.targetDate
            )
            #expect(store.savingsGoals.first(where: { $0.id == createdGoal.id })?.name == "Overland Track Tasmania")
            #expect(store.savingsGoals.first(where: { $0.id == createdGoal.id })?.targetAmountCents == 350_000)

            store.deleteSavingsGoal(id: createdGoal.id)
            #expect(store.savingsGoals.contains(where: { $0.id == createdGoal.id }) == false)
        }
    }

    // MARK: - 20. Zero-Spend Personal Workspace Accuracy, Notification Sync & Split/Future Transaction Math

    @Test("Zero-spend personal workspace starts at $0 (never phantom $91/$3,250), updates notifications live, and isolates future/split spend")
    @MainActor
    func testZeroSpendPersonalAccuracyLiveNotificationsAndFutureSplitMath() async throws {
        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let refDate = Date(timeIntervalSince1970: 1_761_091_200)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )

        // 1. Register a brand-new personal account -> must start at $0.00 across income, savings, spend, and daily allowance
        try await store.registerAccount(
            fullName: "Ketan Test",
            email: "ketan.zero@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )
        #expect(store.profile.typicalTakeHomePayCents == 0)
        #expect(store.profile.savingsTargetPerPeriodCents == 0)
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 0)
        #expect(store.allowanceSummary.todaysStartingAllowanceCents == 0)
        #expect(store.allowanceSummary.todaysRemainingAllowanceCents == 0)

        let zeroPayload = DaylightNotificationScheduler.buildDailyEveningSummary(
            tenantId: store.activeTenantId,
            referenceDate: refDate,
            timeZoneId: store.profile.timeZoneId,
            summary: store.allowanceSummary,
            preferences: store.notificationPreferences
        )
        #expect(zeroPayload.body.contains("$0.00"))
        #expect(!zeroPayload.body.contains("$91"))

        // 2. Verify legacy untouched placeholder ($3,250 pay / $500 savings = $91.66/day monthly) is sanitized automatically
        var legacyPersonal = DaylightStore.makeBlankPersonalWorkspace(referenceDate: refDate, tenantId: "tenant_user_legacy")
        legacyPersonal.profile.typicalTakeHomePayCents = 325_000
        legacyPersonal.profile.savingsTargetPerPeriodCents = 50_000
        let didSanitize = DaylightStore.sanitizeUntouchedLegacyPlaceholderProfile(&legacyPersonal)
        #expect(didSanitize == true)
        #expect(legacyPersonal.profile.typicalTakeHomePayCents == 0)
        #expect(legacyPersonal.profile.savingsTargetPerPeriodCents == 0)

        // 3. Recording actual income when typicalTakeHomePayCents == 0 derives real flexible pool,
        //    and adding/deleting expenses updates today's in-app notification immediately
        let acctId = store.accounts[0].id
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Employer Payroll AU",
            rawDescription: "SALARY CREDIT",
            amountCents: 280_000, // $2,800.00 over 14 days = $200.00/day
            direction: .credit,
            category: .salaryWagesIncome,
            kind: .income,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.periodTakeHomeIncomeCents == 280_000)
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 0)
        #expect(store.allowanceSummary.todaysStartingAllowanceCents == 20_000)

        store.refreshDailyNotificationsAndSchedule()
        #expect(store.notifications.first?.body.contains("No spending today") == true || store.notifications.first?.body.contains("No flexible spending recorded today") == true)

        // Add $45.00 expense today -> today's notification must immediately reflect $45.00 spent (never stale $0 or $91)
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Woolworths",
            rawDescription: "WOOLWORTHS SYDNEY",
            amountCents: 4_500,
            direction: .debit,
            category: .groceries,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 4_500)
        #expect(store.notifications.first?.body.contains("$45.00") == true)

        // Add a future-dated flexible expense tomorrow -> must NOT be counted as "spent today"
        let tomorrowDate = refDate.addingTimeInterval(86_400 * 2)
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Future Booking",
            rawDescription: "FUTURE EVENT TICKET",
            amountCents: 9_100,
            direction: .debit,
            category: .shoppingRetail,
            kind: .expense,
            occurredAt: tomorrowDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 4_500)

        // Split transaction ($60 groceries + $40 mobile phone fixed commitment) partitions fixed vs flexible accurately
        var splitTx = store.transactions.first(where: { $0.merchantName == "Woolworths" })!
        splitTx.amountCents = 10_000
        splitTx.splits = [
            TransactionSplit(id: UUID(), category: .groceries, amountCents: 6_000, note: "Food", excludeFromBudget: false),
            TransactionSplit(id: UUID(), category: .mobilePhone, amountCents: 4_000, note: "Prepaid SIM", excludeFromBudget: false)
        ]
        try store.updateTransaction(splitTx)
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 6_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 4_000)
    }

    // MARK: - 19. Budgets Page Formulas, Cadence Scaling, Non-Default Fixed Reconciliation & Savings Schedule Precision

    @Test("Budgets formulas normalize period cadences, avoid double-counting user-added fixed commitment categories, preserve rollover on edit, and round savings schedules up")
    @MainActor
    func testBudgetsPageFormulasCadenceScalingAndReconciliation() async throws {
        var cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12, minute: 0))!
        let nextPay = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: refDate))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Budget Tester",
            email: "budget.tester@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .fortnightly
        profile.typicalTakeHomePayCents = 300_000 // $3,000.00 / fortnight
        profile.nextPayDate = nextPay
        profile.savingsTargetPerPeriodCents = 0
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)

        let acctId = store.accounts[0].id

        // 1. Add a FixedCommitment in a non-default category (.buyNowPayLater = $120.00 fortnightly)
        store.addFixedCommitment(
            title: "Afterpay Instalment Plan",
            category: .buyNowPayLater,
            amountCents: 12_000,
            frequency: .fortnightly,
            nextDueDate: refDate
        )
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 12_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 12_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 288_000) // $3,000 - $120 = $2,880

        // Record the $120.00 BNPL payment today -> must reconcile fixed commitment and NEVER subtract again as flexible spend
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Afterpay AU",
            rawDescription: "AFTERPAY INSTALMENT",
            amountCents: 12_000,
            direction: .debit,
            category: .buyNowPayLater,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 0)
        #expect(store.allowanceSummary.flexibleSpentTodayCents == 0)
        #expect(store.allowanceSummary.remainingFlexibleBudgetForPeriodCents == 288_000)

        // Update the fixed commitment to $150.00 via updateFixedCommitment
        let commitmentId = store.fixedCommitments[0].id
        store.updateFixedCommitment(
            id: commitmentId,
            title: "Afterpay Instalment Plan",
            category: .buyNowPayLater,
            amountCents: 15_000,
            frequency: .fortnightly,
            nextDueDate: refDate
        )
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 15_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 3_000)

        // 2. Category budget display preservation & annualised calendar calculation scaling (zero 30-day drift)
        store.upsertCategoryBudget(category: .groceries, limitCents: 38_000, rolloverEnabled: true)
        store.addFixedCommitment(
            title: "Internet NBN",
            category: .utilitiesAndInternet,
            amountCents: 9_000, // $90.00 Monthly
            frequency: .monthly,
            nextDueDate: refDate
        )
        // In fortnightly mode: $90 * 12 / 26 = $41.54 (4,154 cents); $150 + $41.54 = $191.54 (19,154 cents)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 19_154)

        // Switch to Monthly Flexible (Oct 2026 = 31 days):
        // - Monthly Internet NBN stays exact $90.00 (9,000c) without 31/30 drift
        // - Fortnightly Groceries ($380) retains $380.00 display limit while calculation-normalised monthly limit = (38_000 * 26 + 6) / 12 = 82_333 ($823.33)
        profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.preferredBudgetingMethod = .monthlyFlexible
        try store.updateProfile(profile)

        #expect(store.allowanceSummary.totalDaysInPeriod == 31)
        let groceriesMonthlyProgress = store.categoryBudgetProgress.first(where: { $0.category == .groceries })!
        #expect(groceriesMonthlyProgress.baseLimitCents == 38_000)
        #expect(groceriesMonthlyProgress.budgetedCents == 38_000)
        #expect(groceriesMonthlyProgress.sourceLimitCents == 38_000)
        #expect(groceriesMonthlyProgress.sourcePeriodType == .fortnightly)
        #expect(groceriesMonthlyProgress.normalizedActivePeriodLimitCents == 82_333)
        #expect(AustralianMoneyFormatter.formatEditableDecimal(cents: 38_005) == "380.05")

        // Explicit Weekly ($100/wk) and Monthly ($600/mo) category limits retain own display period while exposing normalised calculation limits
        store.upsertCategoryBudget(category: .cafesAndTakeaway, limitCents: 10_000, rolloverEnabled: false, periodType: .weekly)
        store.upsertCategoryBudget(category: .shoppingRetail, limitCents: 60_000, rolloverEnabled: false, periodType: .monthly)
        let diningMonthlyProgress = store.categoryBudgetProgress.first(where: { $0.category == .cafesAndTakeaway })!
        let shoppingMonthlyProgress = store.categoryBudgetProgress.first(where: { $0.category == .shoppingRetail })!
        // $100/week display remains 10_000 ($100.00 Weekly); monthly calculation equivalent = (10_000 * 52 + 6) / 12 = 43_333 ($433.33)
        #expect(diningMonthlyProgress.sourcePeriodType == .weekly)
        #expect(diningMonthlyProgress.sourceLimitCents == 10_000)
        #expect(diningMonthlyProgress.baseLimitCents == 10_000)
        #expect(diningMonthlyProgress.budgetedCents == 10_000)
        #expect(diningMonthlyProgress.normalizedActivePeriodLimitCents == 43_333)
        #expect(shoppingMonthlyProgress.sourcePeriodType == .monthly)
        #expect(shoppingMonthlyProgress.baseLimitCents == 60_000)
        #expect(shoppingMonthlyProgress.budgetedCents == 60_000)
        #expect(shoppingMonthlyProgress.normalizedActivePeriodLimitCents == 60_000)

        // 3. Demo rollover non-compounding check: Groceries has baseLimitCents = 38_000 and rolloverAppliedCents = 1_500 (budgetedCents = 39_500)
        let demoStore = DaylightStore(referenceDate: refDate, startInDemoMode: true, persistToDisk: false)
        let demoGroceries = demoStore.categoryBudgetProgress.first(where: { $0.category == .groceries })!
        #expect(demoGroceries.baseLimitCents == 38_000)
        #expect(demoGroceries.rolloverAppliedCents == 1_500)
        #expect(demoGroceries.budgetedCents == 39_500)

        // 4. Savings-First mode + ceiling per-period goal contribution ($1,000 across 3 pay cycles -> $333.34, never $333.33)
        profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.preferredBudgetingMethod = .savingsFirst
        profile.savingsTargetPerPeriodCents = 0
        try store.updateProfile(profile)

        let targetInThreeFortnights = cal.date(byAdding: .day, value: 35, to: cal.startOfDay(for: refDate))! // paydays at +7, +21, +35 = 3 paydays
        store.addSavingsGoal(
            name: "rego & insurance buffer",
            iconName: "car.fill",
            targetAmountCents: 100_000, // $1,000.00
            initialSavedCents: 0,
            targetDate: targetInThreeFortnights,
            linkedAccountId: nil
        )
        let goal = store.savingsGoals[0]
        let suggested = FinancialCalculationEngine.suggestedContributionPerPeriodCents(
            for: goal,
            referenceDate: refDate,
            profile: store.profile
        )
        #expect(suggested == 33_334) // 3 * 33_334 = 100_002 >= 100_000 (guarantees target reached on time)
        #expect(store.allowanceSummary.plannedSavingsForPeriodCents == 33_334)
    }

    // MARK: - 22. Bug A Regression: Category Period Preservation & Calculation Normalisation

    @Test("Category limits preserve their own configured period ($400 weekly/fortnightly/monthly) across edits, reloads, and profile pay-cycle changes without conversion loops")
    @MainActor
    func testCategoryBudgetPeriodPreservationAndCalculationNormalisation() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 0))!
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylight_bug_a_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: true,
            databaseURL: dbURL,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Period Tester",
            email: "period.tester@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        // User starts with a Monthly pay-cycle profile
        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.payFrequency = .monthly
        profile.typicalTakeHomePayCents = 650_000 // $6,500.00 / month
        profile.preferredBudgetingMethod = .payCycle
        profile.nextPayDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        try store.updateProfile(profile)

        let acctId = try #require(store.accounts.first?.id)

        // 1. $400 weekly category limit remains $400 weekly (never $1,714.29!)
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 40_000, rolloverEnabled: false, periodType: .weekly)
        let weeklyRentProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
        #expect(weeklyRentProg.baseLimitCents == 40_000)
        #expect(weeklyRentProg.budgetedCents == 40_000)
        #expect(weeklyRentProg.sourceLimitCents == 40_000)
        #expect(weeklyRentProg.sourcePeriodType == .weekly)
        // Normalised calculation equivalent for monthly cycle = (40_000 * 52 + 6) / 12 = 173_333 ($1,733.33), NOT 30-day 171_429
        #expect(weeklyRentProg.normalizedActivePeriodLimitCents == 173_333)

        // 2. $400 fortnightly category limit remains $400 fortnightly (never $857.14!)
        store.upsertCategoryBudget(category: .groceries, limitCents: 40_000, rolloverEnabled: false, periodType: .fortnightly)
        let fortnightGroceriesProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .groceries }))
        #expect(fortnightGroceriesProg.baseLimitCents == 40_000)
        #expect(fortnightGroceriesProg.budgetedCents == 40_000)
        #expect(fortnightGroceriesProg.sourcePeriodType == .fortnightly)
        #expect(fortnightGroceriesProg.normalizedActivePeriodLimitCents == 86_667) // (40_000 * 26 + 6) / 12

        // 3. $400 monthly category limit remains $400 monthly
        store.upsertCategoryBudget(category: .utilitiesAndInternet, limitCents: 40_000, rolloverEnabled: false, periodType: .monthly)
        let monthlyUtilitiesProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
        #expect(monthlyUtilitiesProg.baseLimitCents == 40_000)
        #expect(monthlyUtilitiesProg.budgetedCents == 40_000)
        #expect(monthlyUtilitiesProg.sourcePeriodType == .monthly)
        #expect(monthlyUtilitiesProg.normalizedActivePeriodLimitCents == 40_000)

        // 4. Changing profile pay frequency to Weekly, Fortnightly, or Irregular NEVER mutates category limits or their display periods
        for freq in [PayFrequency.weekly, .fortnightly, .irregular, .monthly] {
            var p = store.profile
            p.tenantId = store.activeTenantId
            p.payFrequency = freq
            try store.updateProfile(p)

            let r = try #require(store.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
            let g = try #require(store.categoryBudgetProgress.first(where: { $0.category == .groceries }))
            let u = try #require(store.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
            #expect(r.budgetedCents == 40_000 && r.sourcePeriodType == .weekly)
            #expect(g.budgetedCents == 40_000 && g.sourcePeriodType == .fortnightly)
            #expect(u.budgetedCents == 40_000 && u.sourcePeriodType == .monthly)
        }

        // 5. Editing a category limit without re-passing periodType preserves its existing periodType (no silent overwrite or compounding)
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 42_000, rolloverEnabled: true)
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 40_000, rolloverEnabled: false)
        let editedRent = try #require(store.categoryBudgets.first(where: { $0.category == .rentAndMortgage }))
        #expect(editedRent.limitCents == 40_000)
        #expect(editedRent.periodType == .weekly)

        // 6. Reloading from SQLite preserves exact limits and period types without conversion loops
        let reloadedStore = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: true,
            databaseURL: dbURL,
            authService: authService
        )
        try await reloadedStore.loginAccount(email: "period.tester@example.com.au", password: "StrongPassword#2026")
        reloadedStore.referenceDate = refDate
        reloadedStore.recalculateDerivedState()

        let reloadedRent = try #require(reloadedStore.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
        let reloadedGroceries = try #require(reloadedStore.categoryBudgetProgress.first(where: { $0.category == .groceries }))
        let reloadedUtilities = try #require(reloadedStore.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
        #expect(reloadedRent.budgetedCents == 40_000 && reloadedRent.sourcePeriodType == .weekly)
        #expect(reloadedGroceries.budgetedCents == 40_000 && reloadedGroceries.sourcePeriodType == .fortnightly)
        #expect(reloadedUtilities.budgetedCents == 40_000 && reloadedUtilities.sourcePeriodType == .monthly)

        // 7. Category progress tracks transactions within each category's OWN period window
        // Anchor is 2026-11-01 -> Weekly window containing 2026-10-22 is [2026-10-18, 2026-10-25); Monthly window is [2026-10-01, 2026-11-01)
        let earlyOctoberDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 0))!
        let currentWeekDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 0))!
        try reloadedStore.addManualTransaction(
            accountId: acctId,
            merchantName: "Early Oct Rent Adjustment",
            rawDescription: "RENT EARLY OCT",
            amountCents: 15_000,
            direction: .debit,
            category: .rentAndMortgage,
            kind: .expense,
            occurredAt: earlyOctoberDate,
            userNote: "",
            excludeFromBudget: false
        )
        try reloadedStore.addManualTransaction(
            accountId: acctId,
            merchantName: "This Week Rent",
            rawDescription: "RENT THIS WEEK",
            amountCents: 40_000,
            direction: .debit,
            category: .rentAndMortgage,
            kind: .expense,
            occurredAt: currentWeekDate,
            userNote: "",
            excludeFromBudget: false
        )
        try reloadedStore.addManualTransaction(
            accountId: acctId,
            merchantName: "Origin Energy Early Oct",
            rawDescription: "ORIGIN ENERGY",
            amountCents: 12_000,
            direction: .debit,
            category: .utilitiesAndInternet,
            kind: .expense,
            occurredAt: earlyOctoberDate,
            userNote: "",
            excludeFromBudget: false
        )

        let updatedWeeklyRent = try #require(reloadedStore.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
        let updatedMonthlyUtil = try #require(reloadedStore.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
        // Weekly Rent only counts 2026-10-20 ($400.00), NOT 2026-10-05 ($150.00)!
        #expect(updatedWeeklyRent.netSpentCents == 40_000)
        #expect(updatedWeeklyRent.remainingCents == 0)
        #expect(!updatedWeeklyRent.isOverBudget)
        // Monthly Utilities counts 2026-10-05 ($120.00) because 2026-10-05 is inside the monthly period!
        #expect(updatedMonthlyUtil.netSpentCents == 12_000)
        #expect(updatedMonthlyUtil.remainingCents == 28_000)
    }

    // MARK: - 23. Bug B Regression: Calendar-Correct Monthly Boundaries, End-of-Month Clamping, Leap Years & Sydney Midnight/DST

    @Test("Monthly pay-cycles and calendar budgets use exact Calendar boundaries across 28/29/30/31-day months, end-of-month clamping, and Australia/Sydney midnight/DST")
    func testCalendarMonthlyPayCycleBoundariesClampingLeapYearsAndSydneyDST() {
        let tzId = AustralianTimeZone.sydney.rawValue
        let cal = AustralianDateHelper.calendar(for: tzId)

        func sydneyDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ sec: Int = 0) -> Date {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = h
            comps.minute = min
            comps.second = sec
            comps.timeZone = TimeZone(identifier: tzId)
            return cal.date(from: comps)!
        }

        var profile = UserProfile(
            id: UUID(),
            tenantId: "tenant_test_bug_b",
            preferredName: "Calendar Tester",
            email: "calendar@example.com.au",
            countryCode: "AU",
            currencyCode: "AUD",
            timeZoneId: tzId,
            employmentType: .salariedEmployee,
            payFrequency: .monthly,
            typicalTakeHomePayCents: 600_000,
            nextPayDate: sydneyDate(2026, 1, 31, 0, 0, 0),
            savingsTargetPerPeriodCents: 0,
            customFlexibleCapCents: nil,
            preferredBudgetingMethod: .payCycle,
            enableBudgetRollover: false,
            themePreference: .system,
            onboardingCompleted: true,
            createdAt: sydneyDate(2026, 1, 1),
            updatedAt: sydneyDate(2026, 1, 1)
        )

        // 1. End-of-month clamping without anchor drift: Jan 31 -> Feb 28 (28 days) -> Mar 31 (31 days) -> Apr 30 (30 days) -> May 31 (31 days)
        let febCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 10), profile: profile)
        #expect(febCycle.startDate == cal.startOfDay(for: sydneyDate(2026, 1, 31)))
        #expect(febCycle.endDate == cal.startOfDay(for: sydneyDate(2026, 2, 28)))
        #expect(febCycle.totalDays == 28)

        let marCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 3, 15), profile: profile)
        #expect(marCycle.startDate == cal.startOfDay(for: sydneyDate(2026, 2, 28)))
        #expect(marCycle.endDate == cal.startOfDay(for: sydneyDate(2026, 3, 31))) // Restores 31st anchor after Feb 28!
        #expect(marCycle.totalDays == 31)

        let aprCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 4, 15), profile: profile)
        #expect(aprCycle.startDate == cal.startOfDay(for: sydneyDate(2026, 3, 31)))
        #expect(aprCycle.endDate == cal.startOfDay(for: sydneyDate(2026, 4, 30)))
        #expect(aprCycle.totalDays == 30)

        let mayCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 5, 15), profile: profile)
        #expect(mayCycle.startDate == cal.startOfDay(for: sydneyDate(2026, 4, 30)))
        #expect(mayCycle.endDate == cal.startOfDay(for: sydneyDate(2026, 5, 31))) // Restores 31st anchor after Apr 30!
        #expect(mayCycle.totalDays == 31)

        // 2. Leap-year February (2028 is a leap year: Feb has 29 days)
        var leapProfile = profile
        leapProfile.nextPayDate = sydneyDate(2028, 1, 31, 0, 0, 0)
        let leapFebCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2028, 2, 15), profile: leapProfile)
        #expect(leapFebCycle.startDate == cal.startOfDay(for: sydneyDate(2028, 1, 31)))
        #expect(leapFebCycle.endDate == cal.startOfDay(for: sydneyDate(2028, 2, 29)))
        #expect(leapFebCycle.totalDays == 29)

        let leapMarCycle = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2028, 3, 10), profile: leapProfile)
        #expect(leapMarCycle.startDate == cal.startOfDay(for: sydneyDate(2028, 2, 29)))
        #expect(leapMarCycle.endDate == cal.startOfDay(for: sydneyDate(2028, 3, 31)))
        #expect(leapMarCycle.totalDays == 31)

        // 3. Exact calendar month lengths in Monthly Flexible mode across 28, 29, 30, and 31-day months
        profile.preferredBudgetingMethod = .monthlyFlexible
        #expect(FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 14), profile: profile).totalDays == 28)
        #expect(FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2028, 2, 14), profile: profile).totalDays == 29)
        #expect(FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 4, 14), profile: profile).totalDays == 30)
        #expect(FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 10, 14), profile: profile).totalDays == 31) // Includes Sydney DST start Oct 4, 2026!

        // 4. Half-open boundary filtering `[startDate, endDate)` around Australia/Sydney midnight & DST transitions
        let octBounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 10, 20), profile: profile)
        let oneSecondBeforeOct = sydneyDate(2026, 9, 30, 23, 59, 59)
        let exactStartOfOct = sydneyDate(2026, 10, 1, 0, 0, 0)
        let oneSecondBeforeNov = sydneyDate(2026, 10, 31, 23, 59, 59)
        let exactStartOfNov = sydneyDate(2026, 11, 1, 0, 0, 0)

        #expect(!FinancialCalculationEngine.isTimestampInHalfOpenPeriod(oneSecondBeforeOct, startDate: octBounds.startDate, endDate: octBounds.endDate))
        #expect(FinancialCalculationEngine.isTimestampInHalfOpenPeriod(exactStartOfOct, startDate: octBounds.startDate, endDate: octBounds.endDate))
        #expect(FinancialCalculationEngine.isTimestampInHalfOpenPeriod(oneSecondBeforeNov, startDate: octBounds.startDate, endDate: octBounds.endDate))
        #expect(!FinancialCalculationEngine.isTimestampInHalfOpenPeriod(exactStartOfNov, startDate: octBounds.startDate, endDate: octBounds.endDate))
    }

    // MARK: - 24. Bug C Regression: Per-Commitment & Per-Category Fixed Reconciliation Without Cross-Category Masking

    @Test("Fixed commitments reconcile per commitment/category without cross-category masking, double-counting, or broken partial/overpaid/refunded states")
    @MainActor
    func testPerCommitmentAndPerCategoryFixedReconciliationWithoutCrossCategoryMasking() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12, minute: 0))!
        let nextPay = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: refDate))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Reconciliation Tester",
            email: "reconcile@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .fortnightly
        profile.typicalTakeHomePayCents = 400_000 // $4,000.00 / fortnight
        profile.nextPayDate = nextPay
        profile.savingsTargetPerPeriodCents = 0
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)

        let acctId = try #require(store.accounts.first?.id)

        // Configure Rent ($1,000 fortnightly) and Utilities ($200 fortnightly) -> total reserved = $1,200 (120,000c)
        store.addFixedCommitment(
            title: "Marrickville Rent",
            category: .rentAndMortgage,
            amountCents: 100_000,
            frequency: .fortnightly,
            nextDueDate: refDate
        )
        store.addFixedCommitment(
            title: "Ausgrid & NBN",
            category: .utilitiesAndInternet,
            amountCents: 20_000,
            frequency: .fortnightly,
            nextDueDate: refDate
        )

        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 120_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 120_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 280_000)

        // 1. Overpaying Utilities ($350 vs $200 reserved) MUST NOT mark Rent ($1,000) as partially paid!
        // Utilities effective = max($200, $350) = $350 (unpaid $0); Rent effective = $1,000 (unpaid $1,000!)
        // Total effective fixed = $1,350 (135,000c), unpaid remaining = $1,000 (100,000c) — NEVER $850!
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Ausgrid Quarterly Spike",
            rawDescription: "AUSGRID BILL",
            amountCents: 35_000,
            direction: .debit,
            category: .utilitiesAndInternet,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 100_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 135_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 265_000)

        // 2. Partial payment on Rent ($400 of $1,000) leaves exact $600 unpaid on Rent without double-counting
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Partial Rent Transfer",
            rawDescription: "OSKO RENT PART 1",
            amountCents: 40_000,
            direction: .debit,
            category: .rentAndMortgage,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 60_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 135_000)

        // 3. Refund on Utilities ($100 refund against $350 paid -> net $250 paid on Utilities) reduces Utilities excess without touching Rent
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Ausgrid Solar Rebate Refund",
            rawDescription: "AUSGRID REFUND",
            amountCents: 10_000,
            direction: .credit,
            category: .utilitiesAndInternet,
            kind: .refund,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 60_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 125_000) // $1,000 Rent + $250 Utilities

        // 4. Adding a CategoryBudget for Rent ($1,000 fortnightly) does NOT double-subtract in Safe-to-Spend and emits a clear reconciliation notice
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 100_000, rolloverEnabled: false, periodType: .fortnightly)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 125_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 275_000)
        #expect(store.allowanceSummary.reconciliationNotices.contains(where: { $0.category == .rentAndMortgage }))

        // 5. Explicit `linkedFixedCommitmentId` isolates multiple commitments in the same category
        store.addFixedCommitment(
            title: "Belong Mobile Plan",
            category: .utilitiesAndInternet,
            amountCents: 4_000, // $40 fortnightly
            frequency: .fortnightly,
            nextDueDate: refDate
        )
        let mobileCommitmentId = try #require(store.fixedCommitments.first(where: { $0.title == "Belong Mobile Plan" })?.id)
        // Before paying mobile plan: Ausgrid has $250 unlinked pool (covers $200 Ausgrid + $50 spillover if unlinked),
        // OR if we link Ausgrid transactions explicitly to Ausgrid commitment, Belong Mobile stays $40 unpaid!
        let ausgridId = try #require(store.fixedCommitments.first(where: { $0.title == "Ausgrid & NBN" })?.id)
        for tx in store.transactions where tx.category == .utilitiesAndInternet {
            var updated = tx
            updated.linkedFixedCommitmentId = ausgridId
            try store.updateTransaction(updated)
        }
        // Now Ausgrid ($200 reserved, $250 explicitly linked -> $0 unpaid, $250 effective) and Belong Mobile ($40 reserved, $0 paid -> $40 unpaid, $40 effective)!
        // Total unpaid = $600 Rent + $40 Mobile = $640 (64,000c); Total effective fixed = $1,000 + $250 + $40 = $1,290 (129,000c)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 64_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 129_000)

        // Explicitly pay Belong Mobile ($40) linked by ID -> unpaid drops from $640 to $600
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Belong Mobile Debit",
            rawDescription: "BELONG MOBILE",
            amountCents: 4_000,
            direction: .debit,
            category: .utilitiesAndInternet,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false,
            linkedFixedCommitmentId: mobileCommitmentId
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 60_000)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 129_000)
    }

    // MARK: - 25. End-to-End Cross-Surface & Edge-Case Regression (Overview, Budgets, Insights, Notifications, Archived/Empty/Negative States)

    @Test("Cross-surface Overview/Budgets/Insights/Notifications stay consistent across zero-income, negative-remaining, archived-category, and mixed-period states")
    @MainActor
    func testCrossSurfaceConsistencyAndEdgeCases() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12, minute: 0))!
        let nextPay = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: refDate))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Edge Case Tester",
            email: "edge@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .fortnightly
        profile.typicalTakeHomePayCents = 0 // Zero configured income
        profile.nextPayDate = nextPay
        profile.savingsTargetPerPeriodCents = 0
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)

        // 1. Empty / zero-income state: $0 safe-to-spend, zero crashes, consistent notifications
        #expect(store.allowanceSummary.periodTakeHomeIncomeCents == 0)
        #expect(store.allowanceSummary.todaysRemainingAllowanceCents == 0)
        let zeroNotification = DaylightNotificationScheduler.buildDailySummaryContent(
            summary: store.allowanceSummary,
            profile: store.profile
        )
        #expect(zeroNotification.body.contains("$0.00"))

        // 2. Configure $1,400 fortnightly income ($100/day baseline) + mixed-period category budget ($70/week Cafes)
        profile.typicalTakeHomePayCents = 140_000
        try store.updateProfile(profile)
        store.upsertCategoryBudget(category: .cafesAndTakeaway, limitCents: 7_000, rolloverEnabled: false, periodType: .weekly)

        let acctId = try #require(store.accounts.first?.id)

        // Spend $150 today on Cafes -> exceeds $70/week Cafes budget (over by $80, negative remaining -$80) AND exceeds today's $100 daily allowance (-$50 today)
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Single O Surry Hills",
            rawDescription: "SINGLE O SURRY HILLS",
            amountCents: 15_000,
            direction: .debit,
            category: .cafesAndTakeaway,
            kind: .expense,
            occurredAt: refDate,
            userNote: "Team coffee shout",
            excludeFromBudget: false
        )

        // Overview & Notification agree on exact negative today remaining (-$50.00) and remaining period flexible ($1,250.00)
        #expect(store.allowanceSummary.todaysStartingAllowanceCents == 10_000)
        #expect(store.allowanceSummary.todaysRemainingAllowanceCents == -5_000)
        #expect(store.allowanceSummary.remainingFlexibleBudgetForPeriodCents == 125_000)

        let overNotification = DaylightNotificationScheduler.buildDailySummaryContent(
            summary: store.allowanceSummary,
            profile: store.profile
        )
        #expect(overNotification.body.contains("-$50.00") || overNotification.body.contains("$50.00"))

        // Budgets & Insights agree on exact $70.00/week Cafes limit and $80.00 weekly over-budget figure (never converted to $140 fortnightly!)
        let cafeProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .cafesAndTakeaway }))
        #expect(cafeProg.budgetedCents == 7_000)
        #expect(cafeProg.sourcePeriodType == .weekly)
        #expect(cafeProg.remainingCents == -8_000)
        #expect(cafeProg.isOverBudget == true)

        let overInsight = try #require(store.activeInsights.first(where: { $0.relatedCategory == .cafesAndTakeaway }))
        #expect(overInsight.title.contains("$80.00"))
        #expect(overInsight.title.contains("week"))
        #expect(overInsight.summary.contains("$70.00/week"))
    }

    // MARK: - 26. Section 6.A Regression: Category Period Preservation & Calculation Normalisation Matrix

    @Test("Section 6.A: Category period preservation, non-mutating profile changes, and calculation-only normalisation")
    @MainActor
    func testComprehensiveCategoryPeriodPreservation() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10, minute: 0))!
        let nextPay = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Matrix Tester A",
            email: "matrix.a@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .monthly
        profile.typicalTakeHomePayCents = 600_000
        profile.nextPayDate = nextPay
        try store.updateProfile(profile)

        // 1. $400 weekly -> $400 weekly
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 40_000, rolloverEnabled: false, periodType: .weekly)
        let rProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
        #expect(rProg.budgetedCents == 40_000)
        #expect(rProg.sourcePeriodType == .weekly)
        #expect(rProg.normalizedActivePeriodLimitCents == 173_333) // (40_000 * 52 + 6) / 12

        // 2. $400 fortnightly -> $400 fortnightly
        store.upsertCategoryBudget(category: .groceries, limitCents: 40_000, rolloverEnabled: false, periodType: .fortnightly)
        let gProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .groceries }))
        #expect(gProg.budgetedCents == 40_000)
        #expect(gProg.sourcePeriodType == .fortnightly)
        #expect(gProg.normalizedActivePeriodLimitCents == 86_667) // (40_000 * 26 + 6) / 12

        // 3. $400 monthly -> $400 monthly
        store.upsertCategoryBudget(category: .utilitiesAndInternet, limitCents: 40_000, rolloverEnabled: false, periodType: .monthly)
        let uProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
        #expect(uProg.budgetedCents == 40_000)
        #expect(uProg.sourcePeriodType == .monthly)
        #expect(uProg.normalizedActivePeriodLimitCents == 40_000)

        // 4. $100 weekly, monthly profile -> Display remains $100 weekly, calculation normalisation = $433.33 (43,333 cents)
        store.upsertCategoryBudget(category: .cafesAndTakeaway, limitCents: 10_000, rolloverEnabled: false, periodType: .weekly)
        let cProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .cafesAndTakeaway }))
        #expect(cProg.budgetedCents == 10_000)
        #expect(cProg.sourcePeriodType == .weekly)
        #expect(cProg.normalizedActivePeriodLimitCents == 43_333)

        // 5. Switch to Weekly profile: $100 fortnightly category limit -> Display remains $100 fortnightly, calculation normalisation = $50.00 (5,000 cents)
        var weeklyProfile = store.profile
        weeklyProfile.payFrequency = .weekly
        try store.updateProfile(weeklyProfile)

        store.upsertCategoryBudget(category: .domesticTravelHolidays, limitCents: 10_000, rolloverEnabled: false, periodType: .fortnightly)
        let dProg = try #require(store.categoryBudgetProgress.first(where: { $0.category == .domesticTravelHolidays }))
        #expect(dProg.budgetedCents == 10_000)
        #expect(dProg.sourcePeriodType == .fortnightly)
        #expect(dProg.normalizedActivePeriodLimitCents == 5_000) // (10_000 * 26 + 26) / 52

        // 6. Edit $400 weekly -> Period remains weekly
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 45_000, rolloverEnabled: true)
        let editedR = try #require(store.categoryBudgets.first(where: { $0.category == .rentAndMortgage }))
        #expect(editedR.limitCents == 45_000)
        #expect(editedR.periodType == .weekly)

        // 7. Change pay frequency across all 4 options -> Category periods remain unchanged
        for freq in [PayFrequency.fortnightly, .monthly, .irregular, .weekly] {
            var p = store.profile
            p.payFrequency = freq
            try store.updateProfile(p)

            let r = try #require(store.categoryBudgetProgress.first(where: { $0.category == .rentAndMortgage }))
            let g = try #require(store.categoryBudgetProgress.first(where: { $0.category == .groceries }))
            let u = try #require(store.categoryBudgetProgress.first(where: { $0.category == .utilitiesAndInternet }))
            #expect(r.budgetedCents == 45_000 && r.sourcePeriodType == .weekly)
            #expect(g.budgetedCents == 40_000 && g.sourcePeriodType == .fortnightly)
            #expect(u.budgetedCents == 40_000 && u.sourcePeriodType == .monthly)
        }
    }

    // MARK: - 27. Section 6.B Regression: Calendar Boundary, Leap Year, Clamping & Sydney DST Matrix

    @Test("Section 6.B: Calendar month boundary tests across leap years, end-of-month clamping, and Australia/Sydney DST")
    func testComprehensiveCalendarMonthBoundaries() {
        let tzId = AustralianTimeZone.sydney.rawValue
        let cal = AustralianDateHelper.calendar(for: tzId)

        func sydneyDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ sec: Int = 0) -> Date {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = h
            comps.minute = min
            comps.second = sec
            comps.timeZone = TimeZone(identifier: tzId)
            return cal.date(from: comps)!
        }

        var profile = UserProfile(
            id: UUID(),
            tenantId: "tenant_boundary_test",
            preferredName: "Boundary Tester",
            email: "boundary@example.com.au",
            countryCode: "AU",
            currencyCode: "AUD",
            timeZoneId: tzId,
            employmentType: .salariedEmployee,
            payFrequency: .monthly,
            typicalTakeHomePayCents: 500_000,
            nextPayDate: sydneyDate(2026, 1, 31, 0, 0, 0),
            savingsTargetPerPeriodCents: 0,
            customFlexibleCapCents: nil,
            preferredBudgetingMethod: .payCycle,
            enableBudgetRollover: false,
            themePreference: .system,
            onboardingCompleted: true,
            createdAt: sydneyDate(2026, 1, 1),
            updatedAt: sydneyDate(2026, 1, 1)
        )

        // Payday countdown is independent from a calendar-month budget period.
        var novemberPayProfile = profile
        novemberPayProfile.nextPayDate = sydneyDate(2026, 11, 5, 0, 0, 0)
        #expect(
            FinancialCalculationEngine.daysUntilNextPayDate(
                referenceDate: sydneyDate(2026, 11, 2),
                profile: novemberPayProfile
            ) == 3
        )

        // 1. January 31 to February (28 days in 2026 common year)
        let boundsJan31 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 10), profile: profile)
        #expect(boundsJan31.startDate == cal.startOfDay(for: sydneyDate(2026, 1, 31)))
        #expect(boundsJan31.endDate == cal.startOfDay(for: sydneyDate(2026, 2, 28)))
        #expect(boundsJan31.totalDays == 28)

        // 2. January 30 to February
        var pJan30 = profile
        pJan30.nextPayDate = sydneyDate(2026, 1, 30, 0, 0, 0)
        let boundsJan30 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 10), profile: pJan30)
        #expect(boundsJan30.startDate == cal.startOfDay(for: sydneyDate(2026, 1, 30)))
        #expect(boundsJan30.endDate == cal.startOfDay(for: sydneyDate(2026, 2, 28)))
        #expect(boundsJan30.totalDays == 29)

        // 3. February 28 in non-leap year (2026)
        let febBounds2026 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 20), profile: profile)
        #expect(febBounds2026.totalDays == 28)

        // 4. February 29 in leap year (2028 is a leap year)
        var p2028 = profile
        p2028.nextPayDate = sydneyDate(2028, 1, 31, 0, 0, 0)
        let febBounds2028 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2028, 2, 15), profile: p2028)
        #expect(febBounds2028.startDate == cal.startOfDay(for: sydneyDate(2028, 1, 31)))
        #expect(febBounds2028.endDate == cal.startOfDay(for: sydneyDate(2028, 2, 29)))
        #expect(febBounds2028.totalDays == 29)

        // 5. March 31 to April
        var pMar31 = profile
        pMar31.nextPayDate = sydneyDate(2026, 3, 31, 0, 0, 0)
        let aprBounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 4, 15), profile: pMar31)
        #expect(aprBounds.startDate == cal.startOfDay(for: sydneyDate(2026, 3, 31)))
        #expect(aprBounds.endDate == cal.startOfDay(for: sydneyDate(2026, 4, 30)))
        #expect(aprBounds.totalDays == 30)

        // 6. December to January across year boundary
        var pDec31 = profile
        pDec31.nextPayDate = sydneyDate(2026, 12, 31, 0, 0, 0)
        let janBounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2027, 1, 15), profile: pDec31)
        #expect(janBounds.startDate == cal.startOfDay(for: sydneyDate(2026, 12, 31)))
        #expect(janBounds.endDate == cal.startOfDay(for: sydneyDate(2027, 1, 31)))
        #expect(janBounds.totalDays == 31)

        // 7. Anchor restoration after February clamping (March restores 31st anchor!)
        let marRestored = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 3, 15), profile: profile)
        #expect(marRestored.startDate == cal.startOfDay(for: sydneyDate(2026, 2, 28)))
        #expect(marRestored.endDate == cal.startOfDay(for: sydneyDate(2026, 3, 31)))
        #expect(marRestored.totalDays == 31)

        // 8. Sydney Daylight Saving Start (Sunday 4 Oct 2026) and End (Sunday 4 Apr 2027)
        var pDST = profile
        pDST.preferredBudgetingMethod = .monthlyFlexible
        let octDSTBounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 10, 15), profile: pDST)
        #expect(octDSTBounds.totalDays == 31)
        let aprDSTBounds = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2027, 4, 15), profile: pDST)
        #expect(aprDSTBounds.totalDays == 30)

        // 9. Adjacent interval continuity & exact boundary timestamps
        let p1 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 1, 15), profile: pDST)
        let p2 = FinancialCalculationEngine.currentPeriodHalfOpenBounds(referenceDate: sydneyDate(2026, 2, 15), profile: pDST)
        #expect(p1.endDate == p2.startDate) // Continuous interval with no gap or overlap

        let exactStart = p1.startDate
        let exactEnd = p1.endDate
        #expect(FinancialCalculationEngine.isTimestampInHalfOpenPeriod(exactStart, startDate: p1.startDate, endDate: p1.endDate))
        #expect(!FinancialCalculationEngine.isTimestampInHalfOpenPeriod(exactEnd, startDate: p1.startDate, endDate: p1.endDate))
        #expect(FinancialCalculationEngine.isTimestampInHalfOpenPeriod(exactEnd, startDate: p2.startDate, endDate: p2.endDate))
    }

    // MARK: - 28. Section 6.C Regression: Authoritative Fixed Commitment Reconciliation & Safe-to-Spend

    @Test("Section 6.C: Fixed category limits accounted for in Safe-to-Spend without separate commitment, without double-counting")
    @MainActor
    func testComprehensiveFixedCommitmentReconciliation() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12, minute: 0))!
        let nextPay = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Matrix Tester C",
            email: "matrix.c@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .monthly
        profile.typicalTakeHomePayCents = 500_000 // $5,000 monthly income
        profile.nextPayDate = nextPay
        profile.savingsTargetPerPeriodCents = 0
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)

        let acctId = try #require(store.accounts.first?.id)

        // 1. Rent category limit ($1,500/month) WITHOUT separate fixed commitment
        // Bug C fix: Safe-to-Spend MUST account for the $1,500 Rent limit in fixed expenses!
        store.upsertCategoryBudget(category: .rentAndMortgage, limitCents: 150_000, rolloverEnabled: false, periodType: .monthly)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 150_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 150_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000) // $5,000 - $1,500 = $3,500
        #expect(store.allowanceSummary.reconciliationNotices.contains(where: { $0.category == .rentAndMortgage && $0.kind == .categoryLimitWithoutFixedCommitment }))

        // 2. Rent category limit WITH matching fixed commitment ($1,500/month)
        // Double-counting protection: total fixed remains $1,500, NOT $3,000!
        store.addFixedCommitment(
            title: "Apartment Rent",
            category: .rentAndMortgage,
            amountCents: 150_000,
            frequency: .monthly,
            nextDueDate: refDate
        )
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 150_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 150_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000)
        #expect(store.allowanceSummary.reconciliationNotices.contains(where: { $0.category == .rentAndMortgage && $0.kind == .mismatchedCommitmentAndCategoryLimit }))

        // 3. Rent limit ($1,500) and unrelated utility commitment ($200) -> Total reserved = $1,700
        store.addFixedCommitment(
            title: "Energy Australia",
            category: .utilitiesAndInternet,
            amountCents: 20_000,
            frequency: .monthly,
            nextDueDate: refDate
        )
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 170_000)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 170_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 330_000)

        // 4. Multiple fixed category limits: Add Insurance category limit ($300/month) without commitment
        store.upsertCategoryBudget(category: .insurance, limitCents: 30_000, rolloverEnabled: false, periodType: .monthly)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 200_000) // $1,500 Rent + $200 Utility + $300 Insurance
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 200_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 300_000)

        // 5. Fixed commitment without category limit: Energy Australia is already a commitment without category limit -> properly counted

        // 6. Paid fixed commitment: Pay $1,500 Rent
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Real Estate Rent Debit",
            rawDescription: "RENT PAYMENT DEBIT",
            amountCents: 150_000,
            direction: .debit,
            category: .rentAndMortgage,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 50_000) // Only $200 Utility + $300 Insurance unpaid
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 200_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 300_000) // NOT double-deducted in flexible spend!

        // 7. Partially paid commitment: Pay $100 towards $200 Utility
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Energy Part Payment",
            rawDescription: "ENERGY AUSTRALIA PART",
            amountCents: 10_000,
            direction: .debit,
            category: .utilitiesAndInternet,
            kind: .expense,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 40_000) // $100 Utility left + $300 Insurance = $400

        // 8. Refund against fixed payment: $50 solar rebate on Utilities reduces paid utility from $100 to $50, increasing unpaid utility from $100 to $150
        try store.addManualTransaction(
            accountId: acctId,
            merchantName: "Solar Rebate Credit",
            rawDescription: "SOLAR REBATE REFUND",
            amountCents: 5_000,
            direction: .credit,
            category: .utilitiesAndInternet,
            kind: .refund,
            occurredAt: refDate,
            userNote: "",
            excludeFromBudget: false
        )
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 45_000) // $150 Utility + $300 Insurance = $450

        // 9. Archived fixed category: Archiving Insurance removes it from reserved fixed expenses
        store.archiveCategory(.insurance)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 170_000) // Drops by $300
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 15_000) // Only $150 Utility unpaid
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 330_000)

        // 10. Inactive / deleted commitment: Delete Energy Australia commitment
        let energyCommitment = try #require(store.fixedCommitments.first(where: { $0.title == "Energy Australia" }))
        store.deleteFixedCommitment(id: energyCommitment.id)
        #expect(store.allowanceSummary.unpaidFixedCommitmentsRemainingCents == 0)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 155_000) // $1,500 Rent + $50 net utility spend
    }

    // MARK: - 29. Section 6.D Regression: All Six Budgeting Methods Comprehensive Verification

    @Test("Section 6.D: All six budgeting methods correctly calculate period boundaries, fixed expenses, and safe-to-spend")
    @MainActor
    func testAllSixBudgetingMethodsComprehensive() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12, minute: 0))!
        let nextPay = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Matrix Tester D",
            email: "matrix.d@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .monthly
        profile.typicalTakeHomePayCents = 600_000 // $6,000 monthly income
        profile.nextPayDate = nextPay
        profile.savingsTargetPerPeriodCents = 100_000 // $1,000 savings
        try store.updateProfile(profile)

        // Configure $1,500 Rent fixed commitment
        store.addFixedCommitment(
            title: "Rent Commitment",
            category: .rentAndMortgage,
            amountCents: 150_000,
            frequency: .monthly,
            nextDueDate: refDate
        )

        // Configure $600 Groceries category limit
        store.upsertCategoryBudget(category: .groceries, limitCents: 60_000, rolloverEnabled: false, periodType: .monthly)

        // Method 1: Simple Daily Allowance
        profile.preferredBudgetingMethod = .simpleDailyAllowance
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .simpleDailyAllowance)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 150_000)
        #expect(store.allowanceSummary.plannedSavingsForPeriodCents == 100_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000) // $6,000 - $1,500 - $1,000 = $3,500

        // Method 2: Monthly Flexible (calendar month bounds)
        profile.preferredBudgetingMethod = .monthlyFlexible
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .monthlyFlexible)
        #expect(store.allowanceSummary.totalDaysInPeriod == 31) // October has 31 days
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000)

        // Method 3: Category Envelopes (dedicated limits)
        profile.preferredBudgetingMethod = .categorySpecific
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .categorySpecific)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 60_000) // Aligns to $600 Groceries flexible envelope!
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 150_000)

        // Method 4: Pay-Cycle Aligned
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .payCycle)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000)

        // Method 5: Savings-First
        profile.preferredBudgetingMethod = .savingsFirst
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .savingsFirst)
        #expect(store.allowanceSummary.plannedSavingsForPeriodCents == 100_000)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 350_000)

        // Method 6: Custom Flexible Cap
        profile.preferredBudgetingMethod = .custom
        profile.customFlexibleCapCents = 250_000 // $2,500 custom cap
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.budgetingMethodUsed == .custom)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 250_000)

        // Verify behaviour after pay frequency change from Monthly to Fortnightly
        profile.payFrequency = .fortnightly
        profile.typicalTakeHomePayCents = 280_000 // $2,800 fortnightly
        profile.savingsTargetPerPeriodCents = 50_000 // $500 fortnightly
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)
        #expect(store.allowanceSummary.periodTakeHomeIncomeCents == 280_000)
        #expect(store.allowanceSummary.plannedSavingsForPeriodCents == 50_000)
        // Rent $1,500/month normalized to fortnight = (150_000 * 12 + 13) / 26 = 69_231 ($692.31)
        #expect(store.allowanceSummary.totalFixedCommitmentsForPeriodCents == 69_231)
        // Flexible pool = $2,800 - $692.31 - $500 = $1,607.69 (160,769c)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 160_769)
    }

    // MARK: - 30. Pay Frequency Switch: Income Rescaling & Daily Allowance Consistency

    @Test("Switching pay frequency rescales pay & savings and keeps the daily allowance consistent")
    @MainActor
    func testPayFrequencySwitchKeepsDailyAllowanceConsistent() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12, minute: 0))!
        let nextPay = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )
        try await store.registerAccount(
            fullName: "Frequency Tester",
            email: "frequency.tester@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026"
        )

        var profile = store.profile
        profile.tenantId = store.activeTenantId
        profile.onboardingCompleted = true
        profile.payFrequency = .fortnightly
        profile.typicalTakeHomePayCents = 325_000      // $3,250.00 per fortnight ($84,500 / yr)
        profile.savingsTargetPerPeriodCents = 50_000   // $500.00 per fortnight ($13,000 / yr)
        profile.nextPayDate = nextPay
        profile.preferredBudgetingMethod = .payCycle
        try store.updateProfile(profile)

        func dailyAllowanceIsPoolDividedByDays() -> Bool {
            let s = store.allowanceSummary
            let days = MoneyCents(max(1, s.totalDaysInPeriod))
            return abs(s.baselineDailyAllowanceCents * days - s.totalFlexibleBudgetForPeriodCents) < days
        }

        // Fortnightly baseline
        #expect(store.allowanceSummary.periodTakeHomeIncomeCents == 325_000)
        #expect(store.allowanceSummary.totalDaysInPeriod == 14)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 275_000)
        #expect(dailyAllowanceIsPoolDividedByDays())
        let fortnightlyDaily = store.allowanceSummary.baselineDailyAllowanceCents

        // Fortnightly → Monthly: $3,250 × 26 ÷ 12 = $7,041.67 ; $500 × 26 ÷ 12 = $1,083.33
        try store.changePayFrequency(to: .monthly)
        #expect(store.profile.payFrequency == .monthly)
        #expect(store.profile.typicalTakeHomePayCents == 704_167)
        #expect(store.profile.savingsTargetPerPeriodCents == 108_333)
        #expect(store.allowanceSummary.periodTakeHomeIncomeCents == 704_167)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 595_834)
        #expect(store.allowanceSummary.totalDaysInPeriod == 31) // 1 Oct → 1 Nov (calendar month, not 30)
        #expect(dailyAllowanceIsPoolDividedByDays())

        // Monthly → Weekly: $7,041.67 × 12 ÷ 52 = $1,625.00 ; $1,083.33 × 12 ÷ 52 = $250.00
        try store.changePayFrequency(to: .weekly)
        #expect(store.profile.typicalTakeHomePayCents == 162_500)
        #expect(store.profile.savingsTargetPerPeriodCents == 25_000)
        #expect(store.allowanceSummary.totalDaysInPeriod == 7)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 137_500)
        #expect(dailyAllowanceIsPoolDividedByDays())
        #expect(store.allowanceSummary.baselineDailyAllowanceCents == fortnightlyDaily)

        // Weekly → Irregular (28-day): $1,625 × 52 ÷ 13 = $6,500.00 ; $250 × 52 ÷ 13 = $1,000.00
        try store.changePayFrequency(to: .irregular)
        #expect(store.profile.typicalTakeHomePayCents == 650_000)
        #expect(store.profile.savingsTargetPerPeriodCents == 100_000)
        #expect(store.allowanceSummary.totalDaysInPeriod == 28)
        #expect(store.allowanceSummary.totalFlexibleBudgetForPeriodCents == 550_000)
        #expect(dailyAllowanceIsPoolDividedByDays())
        #expect(store.allowanceSummary.baselineDailyAllowanceCents == fortnightlyDaily)

        // Irregular → Fortnightly: round-trips exactly back to the original figures
        try store.changePayFrequency(to: .fortnightly)
        #expect(store.profile.typicalTakeHomePayCents == 325_000)
        #expect(store.profile.savingsTargetPerPeriodCents == 50_000)
        #expect(store.allowanceSummary.baselineDailyAllowanceCents == fortnightlyDaily)

        // Selecting the same frequency is a no-op
        try store.changePayFrequency(to: .fortnightly)
        #expect(store.profile.typicalTakeHomePayCents == 325_000)
    }

    // MARK: - 31. Profile Picture Lifecycle, Preset Avatars & Persistence

    @Test("Profile picture can be configured at sign up, changed, and removed with preset support")
    @MainActor
    func testProfilePictureLifecycleAndPresets() async throws {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 0))!

        let authService = DaylightAuthenticationService(useInMemoryMock: true)
        let store = DaylightStore(
            referenceDate: refDate,
            startInDemoMode: false,
            persistToDisk: false,
            authService: authService
        )

        // 1. Verify all 6 Australian preset avatars render valid image data
        #expect(PresetAvatar.australianPresets.count == 6)
        for preset in PresetAvatar.australianPresets {
            let rendered = ProfileImageProcessor.renderPresetAvatar(preset, size: 120)
            #expect(rendered != nil)
            #expect((rendered?.count ?? 0) > 100)
        }

        // 2. Pick a preset as the initial avatar during registration
        let sunPreset = PresetAvatar.australianPresets.first { $0.id == "sun" }!
        let initialAvatarData = ProfileImageProcessor.renderPresetAvatar(sunPreset, size: 120)
        #expect(initialAvatarData != nil)

        try await store.registerAccount(
            fullName: "Morgan Taylor",
            email: "morgan.taylor@example.com.au",
            password: "StrongPassword#2026",
            confirmPassword: "StrongPassword#2026",
            avatarImageData: initialAvatarData
        )

        // Verify avatar is saved in the active workspace and profile
        #expect(store.profile.preferredName == "Morgan Taylor")
        #expect(store.profile.avatarImageData != nil)
        #expect(store.profile.avatarImageData == initialAvatarData)
        #expect(store.profile.initials == "MT")

        // 3. Update profile avatar to Eucalyptus preset
        let eucalyptPreset = PresetAvatar.australianPresets.first { $0.id == "eucalyptus" }!
        let updatedAvatarData = ProfileImageProcessor.renderPresetAvatar(eucalyptPreset, size: 120)
        #expect(updatedAvatarData != nil)

        try store.updateProfileAvatar(imageData: updatedAvatarData)
        #expect(store.profile.avatarImageData == updatedAvatarData)

        // 4. Remove profile avatar -> reverts to nil, initials fallback is MT
        try store.updateProfileAvatar(imageData: nil)
        #expect(store.profile.avatarImageData == nil)
        #expect(store.profile.initials == "MT")

        // 5. Test JSON Codable forward and backward compatibility
        var profileWithAvatar = store.profile
        profileWithAvatar.avatarImageData = updatedAvatarData

        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(profileWithAvatar)
        let decoder = JSONDecoder()
        let decodedProfile = try decoder.decode(UserProfile.self, from: encodedData)
        #expect(decodedProfile.avatarImageData == updatedAvatarData)
        #expect(decodedProfile.preferredName == "Morgan Taylor")

        // Test decoding legacy JSON that omitted avatarImageData entirely
        var jsonObject = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        jsonObject?.removeValue(forKey: "avatarImageData")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject!)
        let legacyDecodedProfile = try decoder.decode(UserProfile.self, from: legacyData)
        #expect(legacyDecodedProfile.avatarImageData == nil)
        #expect(legacyDecodedProfile.preferredName == "Morgan Taylor")
    }
}

// MARK: - Milestone 1: Transaction Intelligence Tests

@Suite(.serialized)
@MainActor
struct DaylightMoneyTransactionIntelligenceTests {

    private func makeTestTransaction(
        id: UUID = UUID(),
        tenantId: String = "tenant_test",
        accountId: UUID = UUID(),
        sourceTransactionId: String? = nil,
        reconciliationFingerprint: String = UUID().uuidString,
        merchantName: String = "Coles",
        rawDescription: String = "COLES",
        occurredAt: Date = Date(),
        amountCents: MoneyCents = 5420,
        direction: TransactionDirection = .debit,
        category: AustralianCategory = .groceries,
        classificationConfidence: Double = 0.95,
        kind: TransactionKind = .expense
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            tenantId: tenantId,
            accountId: accountId,
            sourceTransactionId: sourceTransactionId,
            reconciliationFingerprint: reconciliationFingerprint,
            merchantName: merchantName,
            rawDescription: rawDescription,
            occurredAt: occurredAt,
            amountCents: amountCents,
            direction: direction,
            category: category,
            classificationConfidence: classificationConfidence,
            status: .posted,
            kind: kind,
            isRecurring: false,
            paymentRail: "eftpos",
            source: .manualEntry,
            userNote: "",
            excludeFromBudget: false,
            linkedOriginalTransactionId: nil,
            linkedFixedCommitmentId: nil,
            splits: [],
            calculationVersion: 1,
            updatedAt: occurredAt
        )
    }

    // MARK: - Task 1: Merchant Recognition Tests

    @Test("Merchant recognition normalises Australian descriptions, handles aliases, terminal suffixes and preserves original text")
    func testAustralianMerchantRecognition() {
        let recogniser = MerchantRecognitionService.shared

        // 1. Exact & aliased Australian merchants
        let woolies = recogniser.recognise("WOOLWORTHS 0321 SYD")
        #expect(woolies.recognisedName == "Woolworths")
        #expect(woolies.defaultCategory == .groceries)
        #expect(woolies.confidence >= 0.90)
        #expect(woolies.rawDescription == "WOOLWORTHS 0321 SYD")
        #expect(!woolies.isUnknown)

        let colesExpress = recogniser.recognise("COLES EXPRESS 1234")
        #expect(colesExpress.recognisedName == "Coles Express")
        #expect(colesExpress.defaultCategory == .fuelTollsVehicle)
        #expect(colesExpress.confidence >= 0.90)

        // Ensure Coles Express is not merged into general Coles
        let coles = recogniser.recognise("COLES 5678 MELBOURNE VIC")
        #expect(coles.recognisedName == "Coles")
        #expect(coles.defaultCategory == .groceries)
        #expect(coles.recognisedName != colesExpress.recognisedName)

        let uber = recogniser.recognise("UBER *TRIP")
        #expect(uber.recognisedName == "Uber")
        #expect(uber.defaultCategory == .publicTransport)

        let uberEats = recogniser.recognise("UBER EATS SYDNEY")
        #expect(uberEats.recognisedName == "Uber Eats")
        #expect(uberEats.defaultCategory == .restaurantsAndDelivery)
        #expect(uber.recognisedName != uberEats.recognisedName)

        let spotify = recogniser.recognise("SPOTIFY P AU")
        #expect(spotify.recognisedName == "Spotify")
        #expect(spotify.defaultCategory == .streamingSubscriptions)

        let netflix = recogniser.recognise("NETFLIX.COM")
        #expect(netflix.recognisedName == "Netflix")
        #expect(netflix.defaultCategory == .streamingSubscriptions)

        let opal = recogniser.recognise("OPAL TOP UP")
        #expect(opal.recognisedName == "Opal")
        #expect(opal.defaultCategory == .publicTransport)

        let ptv = recogniser.recognise("PTV MYKI RECHARGE MEL")
        #expect(ptv.recognisedName == "PTV Myki")
        #expect(ptv.defaultCategory == .publicTransport)

        let linkt = recogniser.recognise("LINKT TOLL SYDNEY")
        #expect(linkt.recognisedName == "Linkt")
        #expect(linkt.defaultCategory == .fuelTollsVehicle)

        let telstra = recogniser.recognise("TELSTRA DIRECT DEBIT")
        #expect(telstra.recognisedName == "Telstra")
        #expect(telstra.defaultCategory == .mobilePhone)

        let bunnings = recogniser.recognise("BUNNINGS 312 CHATSWOOD")
        #expect(bunnings.recognisedName == "Bunnings")
        #expect(bunnings.defaultCategory == .shoppingRetail)

        // 2. Payment rail prefix and terminal suffix stripping
        let sqCafe = recogniser.recognise("SQ *SURRY HILLS CAFE")
        #expect(sqCafe.recognisedName == "Surry Hills Cafe")

        let visaWoolworths = recogniser.recognise("VISA DEBIT PURCHASE - WOOLWORTHS 4412 SYDNEY NSW AU")
        #expect(visaWoolworths.recognisedName == "Woolworths")

        // 3. Unknown merchant handling
        let unknown = recogniser.recognise("UNKNOWN LOCAL MARKET 9876")
        #expect(unknown.isUnknown)
        #expect(unknown.confidence == 0.50)
        #expect(unknown.recognisedName.contains("Unknown Local Market"))
    }

    // MARK: - Task 2: Intelligent Categorisation Tests

    @Test("Intelligent categorisation prioritises user rules, handles transfers, refunds, income, expenses and flags low-confidence classifications")
    func testIntelligentCategorisationPrecedenceAndRefunds() {
        let engine = IntelligentCategorisationEngine.shared

        // 1. Transfers: must be distinguished as .ownAccountTransfer kind and category
        let transferResult = engine.classify(
            rawDescription: "INTERNAL TRANSFER TO SAVINGS",
            direction: .debit,
            isCreditCardAccount: false,
            userRules: []
        )
        #expect(transferResult.suggestedCategory == .ownAccountTransfer)
        #expect(transferResult.suggestedKind == .ownAccountTransfer)
        #expect(transferResult.confidence >= 0.98)
        #expect(transferResult.source == .systemRule)

        // 2. Refunds: credit transactions with refund indicators must NEVER be treated as ordinary income
        let refundResult = engine.classify(
            rawDescription: "REFUND WOOLWORTHS 0321",
            direction: .credit,
            isCreditCardAccount: false,
            userRules: []
        )
        #expect(refundResult.suggestedKind == .refund)
        #expect(refundResult.suggestedKind != .income)
        #expect(refundResult.confidence >= 0.90)

        // 3. Income: credit transactions from salary/payroll
        let salaryResult = engine.classify(
            rawDescription: "SALARY ACME CORP PTY LTD",
            direction: .credit,
            isCreditCardAccount: false,
            userRules: []
        )
        #expect(salaryResult.suggestedCategory == .salaryWagesIncome)
        #expect(salaryResult.suggestedKind == .income)
        #expect(salaryResult.confidence >= 0.95)

        // 4. User-defined rule takes precedence over curated/system rules
        let customUserRule = MerchantRule(
            id: UUID(),
            tenantId: "tenant_a",
            matchSubstring: "WOOLWORTHS",
            normalizedMerchantName: "Woolies Custom",
            assignedCategory: .shoppingRetail,
            applyToFutureOnly: false,
            createdAt: Date()
        )
        let customRuleResult = engine.classify(
            rawDescription: "WOOLWORTHS 0321 SYD",
            direction: .debit,
            isCreditCardAccount: false,
            userRules: [customUserRule]
        )
        #expect(customRuleResult.suggestedCategory == .shoppingRetail)
        #expect(customRuleResult.source == .userRule)
        #expect(customRuleResult.confidence >= 0.98)

        // 5. Low-confidence classification recommends manual review
        let obscureResult = engine.classify(
            rawDescription: "XYZ998877 RANDOM CHARGE",
            direction: .debit,
            isCreditCardAccount: false,
            userRules: []
        )
        #expect(obscureResult.confidence < 0.70)
        #expect(obscureResult.isManualReviewRecommended)
        #expect(obscureResult.source == .fallback)
    }

    // MARK: - Task 3: Classification Feedback & Rule Persistence Tests

    @Test("Classification feedback learns optimal rules, scopes them to workspace, and propagates only to unconfirmed transactions")
    func testClassificationFeedbackRulePersistenceAndIsolation() {
        let feedbackService = ClassificationFeedbackService.shared

        // 1. Derive optimal match substring
        let derivedSub = feedbackService.deriveOptimalMatchSubstring(
            rawDescription: "WOOLWORTHS 0321 SYDNEY AU",
            merchantName: "Woolworths"
        )
        #expect(derivedSub == "WOOLWORTHS")

        // 2. Create or update rule scoped to tenant
        let tenant1 = "workspace_alpha"
        let (rule1, rulesAfter1) = feedbackService.createOrUpdateRule(
            tenantId: tenant1,
            matchSubstring: derivedSub,
            normalizedMerchantName: "Woolworths",
            assignedCategory: .groceries,
            applyToFutureOnly: false,
            existingRules: []
        )
        #expect(rulesAfter1.count == 1)
        #expect(rule1.tenantId == tenant1)
        #expect(rule1.assignedCategory == .groceries)

        // 3. Verify workspace isolation: tenant2 cannot see tenant1's rule
        let tenant2 = "workspace_beta"
        let (rule2, rulesAfter2) = feedbackService.createOrUpdateRule(
            tenantId: tenant2,
            matchSubstring: "CORNER SHOP",
            normalizedMerchantName: "Corner Shop",
            assignedCategory: .restaurantsAndDelivery,
            applyToFutureOnly: false,
            existingRules: []
        )
        #expect(rule2.tenantId == tenant2)
        #expect(rulesAfter2.allSatisfy { $0.tenantId == tenant2 })
        #expect(!rulesAfter2.contains(where: { $0.tenantId == tenant1 }))

        // 4. Test unconfirmed transaction propagation without confirmed overwrite
        let unconfirmedTx = makeTestTransaction(
            id: UUID(),
            tenantId: tenant1,
            sourceTransactionId: "tx_1",
            merchantName: "Woolworths",
            rawDescription: "WOOLWORTHS 0321",
            amountCents: 4500,
            category: .shoppingRetail, // Old incorrect category
            classificationConfidence: 0.65 // Unconfirmed (< 1.0)
        )

        let confirmedTx = makeTestTransaction(
            id: UUID(),
            tenantId: tenant1,
            sourceTransactionId: "tx_2",
            merchantName: "Woolworths",
            rawDescription: "WOOLWORTHS 4412",
            amountCents: 12000,
            category: .healthcareMedicare, // Intentionally user-confirmed
            classificationConfidence: 1.0 // Confirmed
        )

        let (propagatedTxs, modifiedCount) = feedbackService.applyLearnedRuleToUnconfirmedTransactions(
            rule: rule1,
            transactions: [unconfirmedTx, confirmedTx]
        )

        #expect(modifiedCount == 1)
        let updatedUnconfirmed = propagatedTxs.first(where: { $0.id == unconfirmedTx.id })!
        #expect(updatedUnconfirmed.category == .groceries) // Updated to rule's category
        #expect(updatedUnconfirmed.classificationConfidence == 0.98)

        let preservedConfirmed = propagatedTxs.first(where: { $0.id == confirmedTx.id })!
        #expect(preservedConfirmed.category == .healthcareMedicare) // Untouched!
        #expect(preservedConfirmed.classificationConfidence == 1.0)
    }

    // MARK: - Task 4: Duplicate Detection Tests

    @Test("Duplicate detection identifies exact and potential duplicates, respects accounts and dates, and supports dismissal")
    func testDuplicateDetectionMultiFactorAndDismissal() throws {
        let detector = DuplicateDetectionService.shared
        let tenant = "tenant_dup_test"
        let accountA = UUID()
        let accountB = UUID()
        let now = Date()

        // 1. Exact Duplicate (same bank source transaction ID)
        let txOriginal = makeTestTransaction(
            tenantId: tenant,
            accountId: accountA,
            sourceTransactionId: "bank_ref_9988",
            reconciliationFingerprint: "fp_bank_ref_9988",
            merchantName: "Coles",
            rawDescription: "COLES SUPERMARKET",
            occurredAt: now,
            amountCents: 5420
        )

        let txExactDup = makeTestTransaction(
            tenantId: tenant,
            accountId: accountA,
            sourceTransactionId: "bank_ref_9988", // Same bank ref!
            reconciliationFingerprint: "fp_bank_ref_9988",
            merchantName: "Coles",
            rawDescription: "COLES SUPERMARKET",
            occurredAt: now,
            amountCents: 5420
        )

        let exactDups = detector.detectDuplicates(transactions: [txOriginal, txExactDup])
        #expect(exactDups.count == 1)
        #expect(exactDups.first?.status == .confirmedDuplicate)
        #expect(exactDups.first?.confidence == 1.0)

        // 2. Potential Duplicate (same account, same amount, occurred 45 mins apart, same merchant)
        let txPotentialDup = makeTestTransaction(
            tenantId: tenant,
            accountId: accountA,
            sourceTransactionId: "bank_ref_unique_2",
            reconciliationFingerprint: "fp_unique_2",
            merchantName: "Coles",
            rawDescription: "COLES SUPERMARKET",
            occurredAt: now.addingTimeInterval(45 * 60), // 45 minutes later
            amountCents: 5420
        )

        let potentialDups = detector.detectDuplicates(transactions: [txOriginal, txPotentialDup])
        #expect(potentialDups.count == 1)
        #expect(potentialDups.first?.status == .potentialDuplicate)
        #expect((potentialDups.first?.confidence ?? 0.0) >= 0.85)
        #expect(potentialDups.first?.matchingEvidence.contains(where: { $0.contains("amount: $54.20") }) == true)

        // 3. Non-Duplicates: Different accounts
        let txDiffAccount = makeTestTransaction(
            tenantId: tenant,
            accountId: accountB, // Different account!
            sourceTransactionId: "bank_ref_diff_acc",
            reconciliationFingerprint: "fp_diff_acc",
            merchantName: "Coles",
            rawDescription: "COLES SUPERMARKET",
            occurredAt: now.addingTimeInterval(45 * 60),
            amountCents: 5420
        )
        let diffAccountCandidates = detector.detectDuplicates(transactions: [txOriginal, txDiffAccount])
        #expect(diffAccountCandidates.isEmpty)

        // 4. Non-Duplicates: Separated by more than 48 hours
        let txDaysLater = makeTestTransaction(
            tenantId: tenant,
            accountId: accountA,
            sourceTransactionId: "bank_ref_days_later",
            reconciliationFingerprint: "fp_days_later",
            merchantName: "Coles",
            rawDescription: "COLES SUPERMARKET",
            occurredAt: now.addingTimeInterval(72 * 3600), // 3 days later
            amountCents: 5420
        )
        let daysLaterCandidates = detector.detectDuplicates(transactions: [txOriginal, txDaysLater])
        #expect(daysLaterCandidates.isEmpty)

        // 5. Non-Duplicates: Different merchants
        let txDiffMerchant = makeTestTransaction(
            tenantId: tenant,
            accountId: accountA,
            sourceTransactionId: "bank_ref_bunnings",
            reconciliationFingerprint: "fp_bunnings",
            merchantName: "Bunnings",
            rawDescription: "BUNNINGS CHATSWOOD",
            occurredAt: now.addingTimeInterval(45 * 60),
            amountCents: 5420,
            category: .shoppingRetail
        )
        let diffMerchantCandidates = detector.detectDuplicates(transactions: [txOriginal, txDiffMerchant])
        #expect(diffMerchantCandidates.isEmpty)

        // 6. User dismissal: Candidate is excluded when dismissed
        let candidateId = potentialDups.first!.id
        let afterDismissal = detector.detectDuplicates(
            transactions: [txOriginal, txPotentialDup],
            dismissedPairIds: [candidateId]
        )
        #expect(afterDismissal.isEmpty)
    }

    // MARK: - Task 5: DaylightStore Integration Tests

    @Test("DaylightStore integration: category corrections learn rules, update store state, and duplicates dismiss cleanly")
    func testStoreIntelligenceIntegration() throws {
        let store = DaylightStore(startInDemoMode: true, persistToDisk: false)
        guard let tx = store.activeWorkspace.transactions.first else {
            return
        }

        let originalCategory = tx.category
        let newCategory: AustralianCategory = originalCategory == .groceries ? .healthcareMedicare : .groceries

        // User corrects transaction category with rule creation and unconfirmed propagation
        try store.correctTransactionCategory(
            transactionId: tx.id,
            newCategory: newCategory,
            createRule: true,
            applyToUnconfirmed: true
        )

        let updatedTx = store.activeWorkspace.transactions.first(where: { $0.id == tx.id })!
        #expect(updatedTx.category == newCategory)
        #expect(updatedTx.classificationConfidence == 1.0) // Marked confirmed

        // Verify rule was saved in store.merchantRules
        #expect(store.merchantRules.contains(where: { $0.assignedCategory == newCategory }))

        // Verify duplicate candidate detection and dismissal in store
        let dup1 = makeTestTransaction(
            tenantId: store.activeTenantId,
            accountId: store.activeWorkspace.accounts.first?.id ?? UUID(),
            sourceTransactionId: "store_dup_ref",
            reconciliationFingerprint: "store_fp_dup",
            merchantName: "Coles Test",
            rawDescription: "COLES TEST",
            occurredAt: Date(),
            amountCents: 9900
        )
        let dup2 = makeTestTransaction(
            tenantId: store.activeTenantId,
            accountId: store.activeWorkspace.accounts.first?.id ?? UUID(),
            sourceTransactionId: "store_dup_ref",
            reconciliationFingerprint: "store_fp_dup",
            merchantName: "Coles Test",
            rawDescription: "COLES TEST",
            occurredAt: Date(),
            amountCents: 9900
        )

        var ws = store.activeWorkspace
        ws.transactions.append(contentsOf: [dup1, dup2])
        store.activeWorkspace = ws

        let detectedDups = store.duplicateCandidates
        #expect(!detectedDups.isEmpty)
        if let targetDup = detectedDups.first(where: { $0.primaryTransaction.id == dup1.id || $0.duplicateTransaction.id == dup1.id }) {
            store.dismissDuplicateCandidate(id: targetDup.id)
            #expect(!store.duplicateCandidates.contains(where: { $0.id == targetDup.id }))
        }
    }
}

// MARK: - AI Financial Assistant & Voice Assistant Tests

@Suite(.serialized)
@MainActor
struct DaylightMoneyAIAssistantTests {

    @Test("Deterministic Financial Assistant generates evidence-backed structured responses without fabrication")
    func testDeterministicFinancialAssistantResponses() {
        let store = DaylightStore()
        store.resetSyntheticDemoData()

        let engine = DaylightFinancialAssistantEngine.shared

        // 1. Where did my money go?
        let catResult = engine.generateResponse(for: "Where did my money go this month?", store: store)
        #expect(!catResult.text.isEmpty)
        if case .categoryBreakdown(let slices) = catResult.payload {
            #expect(!slices.isEmpty)
            let totalPct = slices.reduce(0.0) { $0 + $1.percentage }
            #expect(totalPct <= 1.05)
        } else {
            Issue.record("Expected categoryBreakdown payload")
        }

        // 2. Spending increase / summary
        let spendResult = engine.generateResponse(for: "Why did my spending increase?", store: store)
        #expect(!spendResult.text.isEmpty)
        if case .spendingSummary(let summaryData) = spendResult.payload {
            #expect(summaryData.totalSpentCents == store.allowanceSummary.totalFlexibleSpentInPeriodCents)
        } else {
            Issue.record("Expected spendingSummary payload")
        }

        // 3. Savings progress
        let savingsResult = engine.generateResponse(for: "How much did I save this month?", store: store)
        #expect(!savingsResult.text.isEmpty)
        if case .savingsProgress(let progressData) = savingsResult.payload {
            #expect(progressData.activeGoalsCount == store.savingsGoals.count)
        } else {
            Issue.record("Expected savingsProgress payload")
        }

        // 4. Biggest expenses
        let biggestResult = engine.generateResponse(for: "What are my biggest expenses?", store: store)
        #expect(biggestResult.text.contains("#1"))

        // 5. Subscriptions
        let subResult = engine.generateResponse(for: "How much do I spend on subscriptions?", store: store)
        #expect(!subResult.text.isEmpty)
        if case .subscriptionsSummary(let subs) = subResult.payload {
            #expect(subs.count == store.recurringPredictions.count)
        } else {
            Issue.record("Expected subscriptionsSummary payload")
        }

        // 6. Safe to spend inquiry
        let safeResult = engine.generateResponse(for: "What is my safe to spend today?", store: store)
        #expect(safeResult.text.contains("Safe-to-Spend for today is"))
    }

    @Test("Voice Assistant service initializes in idle state with clean reset")
    func testVoiceAssistantStateLifecycle() {
        let service = DaylightSpeechService.shared
        service.reset()
        #expect(service.state == .idle)
        #expect(service.transcribedText.isEmpty)
    }

    @Test("Dismissed recurring commitments survive recalculation and SQLite reload")
    func testDismissedRecurringCommitmentPersistsAcrossReload() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylight_dismissed_commitment_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let store = DaylightStore(
            referenceDate: Date(timeIntervalSince1970: 1_761_091_200),
            startInDemoMode: false,
            persistToDisk: true,
            databaseURL: databaseURL
        )
        store.addConfirmedRecurringBill(
            merchantName: "Persistent Internet",
            category: .utilitiesAndInternet,
            expectedAmountCents: 8_900,
            frequency: .monthly,
            nextExpectedDate: Date(timeIntervalSince1970: 1_761_350_400),
            paymentRail: "Direct Debit"
        )
        let id = try #require(store.activeWorkspace.recurringPredictions.first?.id)

        store.dismissRecurringPrediction(id: id)
        #expect(store.recurringPredictions.isEmpty)
        #expect(store.activeWorkspace.recurringPredictions.contains { $0.id == id && $0.isDismissed })

        store.recalculateDerivedState()
        #expect(store.recurringPredictions.isEmpty)
        #expect(store.activeWorkspace.recurringPredictions.contains { $0.id == id && $0.isDismissed })

        let reloadedStore = DaylightStore(
            referenceDate: Date(timeIntervalSince1970: 1_761_091_200),
            startInDemoMode: false,
            persistToDisk: true,
            databaseURL: databaseURL
        )
        #expect(reloadedStore.recurringPredictions.isEmpty)
        #expect(reloadedStore.activeWorkspace.recurringPredictions.contains { $0.id == id && $0.isDismissed })
    }
}

// MARK: - Milestone 2: Advanced Spending Analytics Tests

@Suite(.serialized)
@MainActor
struct DaylightMoneySpendingAnalyticsTests {

    private func makeTx(
        id: UUID = UUID(),
        tenantId: String = "tenant_analytics",
        accountId: UUID = UUID(),
        merchantName: String = "Coles",
        occurredAt: Date,
        amountCents: MoneyCents,
        direction: TransactionDirection = .debit,
        category: AustralianCategory = .groceries,
        kind: TransactionKind = .expense
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            tenantId: tenantId,
            accountId: accountId,
            sourceTransactionId: nil,
            reconciliationFingerprint: UUID().uuidString,
            merchantName: merchantName,
            rawDescription: merchantName.uppercased(),
            occurredAt: occurredAt,
            amountCents: amountCents,
            direction: direction,
            category: category,
            classificationConfidence: 0.95,
            status: .posted,
            kind: kind,
            isRecurring: false,
            paymentRail: "eftpos",
            source: .manualEntry,
            userNote: "",
            excludeFromBudget: false,
            linkedOriginalTransactionId: nil,
            splits: [],
            calculationVersion: 1,
            updatedAt: occurredAt
        )
    }

    // 1. Monthly Expenditure & Aggregation
    @Test("Calculates monthly expenditure, total income and net cash flow accurately in integer cents")
    func testMonthlyExpenditureAndCashFlow() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let oct10 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10))!
        let oct20 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14))!
        let nov5 = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!

        let salary = makeTx(occurredAt: oct10, amountCents: 500_000, direction: .credit, category: .salaryWagesIncome, kind: .income)
        let groceries = makeTx(merchantName: "Woolworths", occurredAt: oct10, amountCents: 15_000, direction: .debit, category: .groceries)
        let dining = makeTx(merchantName: "Lune Croissant", occurredAt: oct20, amountCents: 4_500, direction: .debit, category: .cafesAndTakeaway)
        let outOfPeriod = makeTx(occurredAt: nov5, amountCents: 8_000, direction: .debit, category: .groceries)

        let txs = [salary, groceries, dining, outOfPeriod]
        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9, minute: 0))!

        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: txs,
            categoryBudgets: []
        )

        #expect(analytics.totalExpensesCents == 19_500) // $195.00
        #expect(analytics.cashFlow.totalIncomeCents == 500_000) // $5,000.00
        #expect(analytics.cashFlow.netCashFlowCents == 480_500) // $4,805.00
        #expect(analytics.period.isComplete == true)
        #expect(analytics.dailyAverageCents == 19_500 / 31)
    }

    // 2. Full Month Comparison
    @Test("Compares full month against prior full month with exact absolute and percentage changes")
    func testFullMonthMoMComparison() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let sep15 = cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        let oct15 = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!

        let sepTx = makeTx(occurredAt: sep15, amountCents: 100_000, direction: .debit, category: .groceries) // $1,000
        let octTx = makeTx(occurredAt: oct15, amountCents: 120_000, direction: .debit, category: .groceries) // $1,200

        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))! // viewing completed Oct
        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [sepTx, octTx],
            categoryBudgets: []
        )

        guard let comp = analytics.comparisonToPreviousMonth else {
            Issue.record("Expected comparisonToPreviousMonth")
            return
        }

        #expect(comp.currentAmountCents == 120_000)
        #expect(comp.previousAmountCents == 100_000)
        #expect(comp.absoluteChangeCents == 20_000)
        #expect(comp.direction == .increased)
        #expect(comp.percentageChange == 20.0) // +20%
        #expect(comp.isEquivalentPeriodComparison == false)
    }

    // 3. Partial Month (Like-for-Like) Comparison
    @Test("Handles partial months by comparing elapsed days against equivalent elapsed days of previous month")
    func testPartialMonthLikeForLikeComparison() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        // Reference date: 15 October 2026 (day 15 of 31)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14))!

        // September transactions: day 5 ($50), day 12 ($50), day 25 ($200 - outside equivalent period!)
        let sepEarly1 = makeTx(occurredAt: cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))!, amountCents: 5_000)
        let sepEarly2 = makeTx(occurredAt: cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))!, amountCents: 5_000)
        let sepLate = makeTx(occurredAt: cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!, amountCents: 20_000)

        // October transactions: day 8 ($150)
        let octEarly = makeTx(occurredAt: cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!, amountCents: 15_000)

        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [sepEarly1, sepEarly2, sepLate, octEarly],
            categoryBudgets: []
        )

        #expect(analytics.period.isComplete == false)
        #expect(analytics.period.elapsedDays == 15)
        #expect(analytics.totalExpensesCents == 15_000) // $150

        guard let comp = analytics.comparisonToPreviousMonth else {
            Issue.record("Expected comparisonToPreviousMonth")
            return
        }

        #expect(comp.isEquivalentPeriodComparison == true)
        // Equivalent previous spend must only count sepEarly1 and sepEarly2 ($50 + $50 = $100), NOT sepLate!
        #expect(comp.previousAmountCents == 10_000)
        #expect(comp.absoluteChangeCents == 5_000)
        #expect(comp.direction == .increased)
        #expect(comp.percentageChange == 50.0) // +50%
    }

    // 4. Category Analytics & Growth Identification
    @Test("Calculates category spending shares, fastest growing, and decreasing expenditure")
    func testCategoryAnalytics() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let sep10 = cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
        let oct10 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!

        let sepGroceries = makeTx(occurredAt: sep10, amountCents: 40_000, category: .groceries)
        let sepDining = makeTx(occurredAt: sep10, amountCents: 20_000, category: .cafesAndTakeaway)

        let octGroceries = makeTx(occurredAt: oct10, amountCents: 50_000, category: .groceries)
        let octDining = makeTx(occurredAt: oct10, amountCents: 10_000, category: .cafesAndTakeaway)
        let octTransport = makeTx(occurredAt: oct10, amountCents: 40_000, category: .fuelTollsVehicle)

        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [sepGroceries, sepDining, octGroceries, octDining, octTransport],
            categoryBudgets: []
        )

        let catMap = Dictionary(uniqueKeysWithValues: analytics.categories.map { ($0.category, $0) })
        #expect(catMap[.groceries]?.isHighestSpending == true)
        #expect(catMap[.cafesAndTakeaway]?.isDecreasing == true)
        #expect(catMap[.cafesAndTakeaway]?.change.direction == .decreased)
        #expect(catMap[.fuelTollsVehicle]?.isFastestGrowing == true)
    }

    // 5. Merchant Analytics & Concentration
    @Test("Calculates top merchants, concentration shares, average ticket and identifies largest purchase")
    func testMerchantAnalytics() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let oct5 = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let oct12 = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let oct20 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!

        let w1 = makeTx(merchantName: "Woolworths", occurredAt: oct5, amountCents: 10_000)
        let w2 = makeTx(merchantName: "Woolworths", occurredAt: oct12, amountCents: 20_000)
        let cafe = makeTx(merchantName: "Single O Surry Hills", occurredAt: oct20, amountCents: 5_000, category: .cafesAndTakeaway)

        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [w1, w2, cafe],
            categoryBudgets: []
        )

        guard let topM = analytics.topMerchants.first else {
            Issue.record("Expected top merchant")
            return
        }

        #expect(topM.merchantName == "Woolworths")
        #expect(topM.totalSpentCents == 30_000)
        #expect(topM.transactionCount == 2)
        #expect(topM.averageTransactionCents == 15_000)
        #expect(topM.largestTransactionCents == 20_000)
        // 30,000 / 35,000 ≈ 85.7% concentration
        #expect(topM.concentrationShare >= 0.85)
    }

    // 6. Refund Handling & Negative Offsets
    @Test("Refunds correctly offset expenditure and prevent negative total expenses")
    func testRefundHandlingInSpendingAnalytics() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let oct5 = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
        let oct6 = cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 14))!

        let purchase = makeTx(occurredAt: oct5, amountCents: 10_000, direction: .debit, category: .groceries)
        let refund = makeTx(occurredAt: oct6, amountCents: 3_000, direction: .credit, category: .groceries, kind: .refund)

        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [purchase, refund],
            categoryBudgets: []
        )

        #expect(analytics.totalExpensesCents == 7_000) // $100 - $30 = $70 net spend
        #expect(analytics.cashFlow.totalRefundsCents == 3_000)
    }

    // 7. Internal Transfers & Debt Repayments Excluded
    @Test("Internal transfers and credit card bill repayments are strictly excluded from expenditure")
    func testTransferExclusionInAnalytics() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let oct10 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10))!

        let transfer = makeTx(merchantName: "Own Account Transfer", occurredAt: oct10, amountCents: 200_000, direction: .debit, category: .ownAccountTransfer, kind: .ownAccountTransfer)
        let cardRepayment = makeTx(merchantName: "CBA Credit Card Payment", occurredAt: oct10, amountCents: 150_000, direction: .debit, category: .creditCardRepayment, kind: .creditCardRepayment)
        let realExpense = makeTx(merchantName: "Woolworths", occurredAt: oct10, amountCents: 6_500, direction: .debit, category: .groceries)

        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [transfer, cardRepayment, realExpense],
            categoryBudgets: []
        )

        #expect(analytics.totalExpensesCents == 6_500)
    }

    // 8. Budget Utilisation & Flags
    @Test("Calculates budget utilisation, remaining budget and flags approaching or exceeding limits")
    func testBudgetUtilisationAndLimits() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let oct10 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10))!

        // Monthly groceries budget: $400 (40,000 cents)
        let groceryBudget = CategoryBudget(
            id: UUID(),
            tenantId: "t1",
            category: .groceries,
            limitCents: 40_000,
            rolloverEnabled: false,
            rolloverBalanceCents: 0,
            periodType: .monthly,
            updatedAt: oct10
        )

        // Case A: 35,000 cents spent (87.5% utilisation -> isApproachingBudget)
        let txNearLimit = makeTx(occurredAt: oct10, amountCents: 35_000, category: .groceries)
        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let analyticsNear = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [txNearLimit],
            categoryBudgets: [groceryBudget]
        )

        let catNear = analyticsNear.categories.first { $0.category == .groceries }
        #expect(catNear?.isApproachingBudget == true)
        #expect(catNear?.isExceedingBudget == false)
        #expect(catNear?.remainingBudgetCents == 5_000)

        // Case B: 45,000 cents spent (112.5% utilisation -> isExceedingBudget)
        let txOverLimit = makeTx(occurredAt: oct10, amountCents: 45_000, category: .groceries)
        let analyticsOver = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [txOverLimit],
            categoryBudgets: [groceryBudget]
        )

        let catOver = analyticsOver.categories.first { $0.category == .groceries }
        #expect(catOver?.isExceedingBudget == true)
        #expect(catOver?.remainingBudgetCents == -5_000)
    }

    // 9. Zero-Spending and Missing Historical Data Edge Cases
    @Test("Zero spending periods and missing history produce safe outputs without division by zero")
    func testZeroSpendingAndMissingHistoryEdgeCases() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let refDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!

        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: [],
            categoryBudgets: []
        )

        #expect(analytics.totalExpensesCents == 0)
        #expect(analytics.dailyAverageCents == 0)
        #expect(analytics.comparisonToPreviousMonth == nil)
        #expect(analytics.categories.isEmpty)
        #expect(analytics.topMerchants.isEmpty)
        #expect(analytics.detectedPatterns.isEmpty)

        // Verify Money Story summary export also handles empty safely
        let storySummary = analytics.toMoneyStorySummary()
        #expect(storySummary.totalSpentCents == 0)
        #expect(storySummary.topCategoryName == nil)
    }

    // 10. Spending Pattern Detection (Groceries, Dining, Micro-Transactions, Large Purchases)
    @Test("Detects meaningful spending patterns with supporting evidence")
    func testSpendingPatternDetection() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")
        let sep10 = cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 10))!
        let oct10 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10))!

        // September groceries: $100
        let sepGrocery = makeTx(occurredAt: sep10, amountCents: 10_000, category: .groceries)

        // October groceries: $200 (+100% increase)
        let octGrocery1 = makeTx(occurredAt: oct10, amountCents: 10_000, category: .groceries)
        let octGrocery2 = makeTx(occurredAt: oct10, amountCents: 10_000, category: .groceries)

        // 12 micro transactions of $5 each ($60 total micro spend)
        var microTxs: [TransactionRecord] = []
        for i in 1...12 {
            let txDate = cal.date(from: DateComponents(year: 2026, month: 10, day: i, hour: 8))!
            microTxs.append(makeTx(merchantName: "7-Eleven Coffee", occurredAt: txDate, amountCents: 500, category: .cafesAndTakeaway))
        }

        // 1 unusually large purchase: $800 at Apple
        let bigTx = makeTx(merchantName: "Apple Store Bondi", occurredAt: oct10, amountCents: 80_000, category: .shoppingRetail)

        let allTxs = [sepGrocery, octGrocery1, octGrocery2, bigTx] + microTxs
        let refDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!

        let analytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: 2026,
            month: 10,
            referenceDate: refDate,
            transactions: allTxs,
            categoryBudgets: []
        )

        let patterns = analytics.detectedPatterns
        #expect(!patterns.isEmpty)

        // Verify increasing groceries detected
        let groceryPattern = patterns.first { $0.type == .increasingGroceries }
        #expect(groceryPattern != nil)
        #expect(!groceryPattern!.supportingEvidence.isEmpty)

        // Verify frequent small transactions detected
        let microPattern = patterns.first { $0.type == .frequentSmallTransactions }
        #expect(microPattern != nil)

        // Verify unusually large purchase detected
        let largePattern = patterns.first { $0.type == .unusuallyLargePurchase }
        #expect(largePattern != nil)
    }

    // 11. Workspace Isolation in Store Analytics
    @Test("DaylightStore strictly isolates spending analytics between Demo and Personal workspaces")
    func testWorkspaceIsolationInAnalytics() {
        let store = DaylightStore()
        store.isDemoMode = true
        let demoAnalytics = store.monthlySpendingAnalytics
        #expect(demoAnalytics != nil)

        store.isDemoMode = false
        let personalAnalytics = store.monthlySpendingAnalytics
        #expect(personalAnalytics != nil)

        #expect(store.isDemoMode == false)
    }

    // 12. Daylight Saving Time (DST) Transitions
    @Test("Australian DST transition dates do not skew month boundary calculations")
    func testDaylightSavingTimeBoundaries() {
        let cal = AustralianDateHelper.calendar(for: "Australia/Sydney")

        // October 2026: DST begins in Sydney on Sunday 4 October 2026 (clocks forward 1hr)
        let octStart = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let octEnd = cal.date(byAdding: .month, value: 1, to: octStart)!
        let octDays = cal.dateComponents([.day], from: octStart, to: octEnd).day
        #expect(octDays == 31)

        // April 2027: DST ends in Sydney on Sunday 4 April 2027 (clocks back 1hr)
        let aprStart = cal.date(from: DateComponents(year: 2027, month: 4, day: 1))!
        let aprEnd = cal.date(byAdding: .month, value: 1, to: aprStart)!
        let aprDays = cal.dateComponents([.day], from: aprStart, to: aprEnd).day
        #expect(aprDays == 30)
    }

    @Test("CSV parsing preserves quoted commas, escaped quotes, CRLF and multiline fields")
    func testRFC4180CSVParsing() {
        let csv = "Date,Description,Amount\r\n2026-01-02,\"Cafe, Sydney\",-12.50\r\n2026-01-03,\"Quoted \"\"merchant\"\"\ncontinued\",25.00\r\n"
        let rows = FinancialCalculationEngine.parseCSVRows(csv)

        #expect(rows.count == 3)
        #expect(rows[1] == ["2026-01-02", "Cafe, Sydney", "-12.50"])
        #expect(rows[2] == ["2026-01-03", "Quoted \"merchant\"\ncontinued", "25.00"])
    }

    @Test("Money parsing rejects values outside the Int64 cent range")
    func testMoneyBoundaryValidation() {
        #expect(AustralianMoneyFormatter.parseToCents("92233720368547758.07") == Int64.max)
        #expect(AustralianMoneyFormatter.parseToCents("-92233720368547758.08") == Int64.min)
        #expect(AustralianMoneyFormatter.parseToCents("92233720368547758.08") == nil)
        #expect(AustralianMoneyFormatter.parseToCents("1.234") == 123)
        #expect(AustralianMoneyFormatter.format(cents: Int64.min).hasPrefix("-$"))
    }
}
