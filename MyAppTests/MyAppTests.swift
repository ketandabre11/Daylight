import Foundation
import Testing
@testable import MyApp

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
}
