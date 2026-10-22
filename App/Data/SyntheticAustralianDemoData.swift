import Foundation

extension DaylightStore {
    // MARK: - Blank Personal Workspace (Isolated from Demo Data)

    public static func makeBlankPersonalWorkspace(
        referenceDate: Date,
        tenantId: String = personalTenantId,
        preferredName: String = "",
        email: String = "",
        onboardingCompleted: Bool = false,
        includeDefaultEverydayAccount: Bool = false
    ) -> TenantWorkspaceSnapshot {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let nextPay = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: referenceDate)) ?? referenceDate.addingTimeInterval(14 * 86400)

        let profile = UserProfile(
            id: UUID(),
            tenantId: tenantId,
            preferredName: preferredName,
            email: email,
            countryCode: "AU",
            currencyCode: "AUD",
            timeZoneId: AustralianTimeZone.sydney.rawValue,
            employmentType: .salariedEmployee,
            payFrequency: .fortnightly,
            typicalTakeHomePayCents: 325_000, // $3,250.00 fortnightly default suggestion
            nextPayDate: nextPay,
            savingsTargetPerPeriodCents: 50_000, // $500.00 fortnightly default suggestion
            customFlexibleCapCents: nil,
            preferredBudgetingMethod: .payCycle,
            enableBudgetRollover: false,
            themePreference: .system,
            onboardingCompleted: onboardingCompleted,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )

        let initialAccounts: [FinancialAccount] = includeDefaultEverydayAccount ? [
            FinancialAccount(
                id: UUID(),
                tenantId: tenantId,
                institutionName: "Australian Bank Account (Manual)",
                nickname: "Everyday Spending",
                accountType: .everydayTransaction,
                maskedAccountNumber: "•••• 1001",
                currencyCode: "AUD",
                availableBalanceCents: 0,
                currentBalanceCents: 0,
                balanceUpdatedAt: referenceDate,
                connectionStatus: .manual,
                lastSuccessfulSyncAt: referenceDate,
                lastSyncErrorMessage: nil,
                dataCoverageDescription: "Manual entries & CSV statements",
                consentRecordId: nil,
                includeInSafeToSpendCash: true
            )
        ] : []

        return TenantWorkspaceSnapshot(
            tenantId: tenantId,
            profile: profile,
            accounts: initialAccounts,
            consentRecords: [],
            transactions: [],
            merchantRules: [],
            fixedCommitments: [],
            categoryBudgets: [],
            recurringPredictions: [],
            savingsGoals: [],
            notificationPreferences: NotificationPreferences(
                dailySummaryEnabled: true,
                dailySummaryHour: 19,
                budgetThresholdAlertsEnabled: true,
                upcomingBillRemindersEnabled: true,
                paydayRemindersEnabled: true,
                recurringChangeAlertsEnabled: true,
                unusualSpendingAlertsEnabled: true,
                hideExactAmountsInPreviews: false
            ),
            notifications: [],
            importJobs: [],
            auditEvents: [],
            processedIdempotencyKeys: []
        )
    }

    // MARK: - Synthetic Australian Demo Workspace

    public static func makeSyntheticAustralianDemoWorkspace(referenceDate: Date) -> TenantWorkspaceSnapshot {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let todayStart = cal.startOfDay(for: referenceDate)

        func daysOffset(_ days: Int, hour: Int = 11, minute: Int = 15) -> Date {
            let base = cal.date(byAdding: .day, value: days, to: todayStart) ?? todayStart
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        // Next payday in 6 days (so we are Day 8 of a 14-day Australian fortnightly pay cycle)
        let nextPayDate = daysOffset(6, hour: 9, minute: 0)

        let profile = UserProfile(
            id: UUID(),
            tenantId: demoTenantId,
            preferredName: "Alex",
            email: "alex.demo@example.com.au",
            countryCode: "AU",
            currencyCode: "AUD",
            timeZoneId: AustralianTimeZone.sydney.rawValue,
            employmentType: .salariedEmployee,
            payFrequency: .fortnightly,
            typicalTakeHomePayCents: 325_000, // $3,250.00 per fortnight ($6,500.00 per 28 days)
            nextPayDate: nextPayDate,
            savingsTargetPerPeriodCents: 50_000, // $500.00 per fortnight ($1,000.00 per 28 days)
            customFlexibleCapCents: nil,
            preferredBudgetingMethod: .payCycle,
            enableBudgetRollover: false,
            themePreference: .system,
            onboardingCompleted: true,
            createdAt: daysOffset(-60),
            updatedAt: referenceDate
        )

        // Synthetic Consent Record (clearly marked as Sandbox Simulation)
        let consentId = UUID()
        let demoConsent = ConsentRecord(
            id: consentId,
            tenantId: demoTenantId,
            institutionName: "Synthetic Demo Bank AU (CDR Sandbox)",
            providerAdapterName: "DaylightCDRAdapter (Mock Sandbox)",
            scopesGranted: [
                "bank:accounts.basic:read",
                "bank:accounts.detail:read",
                "bank:transactions:read"
            ],
            grantedAt: daysOffset(-45),
            expiresAt: daysOffset(320),
            revokedAt: nil,
            isSandboxSimulation: true,
            statusNote: "Synthetic CDR Consent Simulation — No live bank connection"
        )

        // Synthetic Accounts
        let everydayAccountId = UUID()
        let savingsAccountId = UUID()
        let creditCardAccountId = UUID()

        let accounts: [FinancialAccount] = [
            FinancialAccount(
                id: everydayAccountId,
                tenantId: demoTenantId,
                institutionName: "Southern Cross Bank (Demo)",
                nickname: "Everyday Spending",
                accountType: .everydayTransaction,
                maskedAccountNumber: "•••• 4821",
                currencyCode: "AUD",
                availableBalanceCents: 284_050, // $2,840.50 available
                currentBalanceCents: 289_500,   // $2,895.00 ledger (includes pending holds)
                balanceUpdatedAt: referenceDate,
                connectionStatus: .demoSynthetic,
                lastSuccessfulSyncAt: referenceDate,
                lastSyncErrorMessage: nil,
                dataCoverageDescription: "90 days of synthetic AUD transactions (Osko, BPAY, eftpos)",
                consentRecordId: consentId,
                includeInSafeToSpendCash: true
            ),
            FinancialAccount(
                id: savingsAccountId,
                tenantId: demoTenantId,
                institutionName: "Southern Cross Bank (Demo)",
                nickname: "Home Deposit & Emergency Saver",
                accountType: .highInterestSavings,
                maskedAccountNumber: "•••• 9012",
                currencyCode: "AUD",
                availableBalanceCents: 1_845_000, // $18,450.00
                currentBalanceCents: 1_845_000,
                balanceUpdatedAt: referenceDate,
                connectionStatus: .demoSynthetic,
                lastSuccessfulSyncAt: referenceDate,
                lastSyncErrorMessage: nil,
                dataCoverageDescription: "Savings & internal transfers",
                consentRecordId: consentId,
                includeInSafeToSpendCash: false
            ),
            FinancialAccount(
                id: creditCardAccountId,
                tenantId: demoTenantId,
                institutionName: "Tasman Card Services (Demo)",
                nickname: "Everyday Rewards Visa",
                accountType: .creditCard,
                maskedAccountNumber: "•••• 3319",
                currencyCode: "AUD",
                availableBalanceCents: 538_000, // $5,380.00 available credit
                currentBalanceCents: -62_000,   // -$620.00 owing
                balanceUpdatedAt: referenceDate,
                connectionStatus: .demoSynthetic,
                lastSuccessfulSyncAt: referenceDate,
                lastSyncErrorMessage: nil,
                dataCoverageDescription: "Card purchases, refunds & monthly BPAY repayments",
                consentRecordId: nil,
                includeInSafeToSpendCash: false
            )
        ]

        // Fixed Commitments for the fortnight ($1,150.00 total per fortnight = $2,300 per 28 days)
        let fixedCommitments: [FixedCommitment] = [
            FixedCommitment(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Fortnightly Rent (Marrickville)",
                category: .rentAndMortgage,
                amountCents: 92_000, // $920.00/fn
                frequency: .fortnightly,
                nextDueDate: daysOffset(5),
                isConfirmed: true
            ),
            FixedCommitment(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Utilities, NBN & Mobile Reserve",
                category: .utilitiesAndInternet,
                amountCents: 13_500, // $135.00/fn
                frequency: .fortnightly,
                nextDueDate: daysOffset(3),
                isConfirmed: true
            ),
            FixedCommitment(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Health Insurance & Gym",
                category: .insurance,
                amountCents: 9_500, // $95.00/fn
                frequency: .fortnightly,
                nextDueDate: daysOffset(4),
                isConfirmed: true
            )
        ]

        // Category Budgets for the active fortnight
        let categoryBudgets: [CategoryBudget] = [
            CategoryBudget(
                id: UUID(),
                tenantId: demoTenantId,
                category: .groceries,
                limitCents: 38_000, // $380.00/fn
                rolloverEnabled: true,
                rolloverBalanceCents: 1_500,
                periodType: .fortnightly,
                updatedAt: referenceDate
            ),
            CategoryBudget(
                id: UUID(),
                tenantId: demoTenantId,
                category: .cafesAndTakeaway,
                limitCents: 12_000, // $120.00/fn
                rolloverEnabled: false,
                rolloverBalanceCents: 0,
                periodType: .fortnightly,
                updatedAt: referenceDate
            ),
            CategoryBudget(
                id: UUID(),
                tenantId: demoTenantId,
                category: .restaurantsAndDelivery,
                limitCents: 16_000, // $160.00/fn
                rolloverEnabled: false,
                rolloverBalanceCents: 0,
                periodType: .fortnightly,
                updatedAt: referenceDate
            ),
            CategoryBudget(
                id: UUID(),
                tenantId: demoTenantId,
                category: .publicTransport,
                limitCents: 9_000, // $90.00/fn
                rolloverEnabled: false,
                rolloverBalanceCents: 0,
                periodType: .fortnightly,
                updatedAt: referenceDate
            ),
            CategoryBudget(
                id: UUID(),
                tenantId: demoTenantId,
                category: .shoppingRetail,
                limitCents: 20_000, // $200.00/fn
                rolloverEnabled: false,
                rolloverBalanceCents: 0,
                periodType: .fortnightly,
                updatedAt: referenceDate
            )
        ]

        // Helper to build synthetic transactions
        let medicalTxId = UUID()
        func makeTx(
            id: UUID = UUID(),
            accountId: UUID,
            dayOffset: Int,
            hour: Int = 12,
            merchant: String,
            raw: String,
            cents: MoneyCents,
            direction: TransactionDirection = .debit,
            category: AustralianCategory,
            confidence: Double = 0.96,
            status: TransactionStatus = .posted,
            kind: TransactionKind = .expense,
            isRecurring: Bool = false,
            rail: String = "eftpos / Card",
            note: String = "",
            exclude: Bool = false,
            linkedId: UUID? = nil
        ) -> TransactionRecord {
            let date = daysOffset(dayOffset, hour: hour)
            let fp = FinancialCalculationEngine.makeReconciliationFingerprint(
                accountId: accountId,
                date: date,
                amountCents: cents,
                direction: direction,
                rawDescription: raw,
                sourceTransactionId: id.uuidString
            )
            return TransactionRecord(
                id: id,
                tenantId: demoTenantId,
                accountId: accountId,
                sourceTransactionId: id.uuidString,
                reconciliationFingerprint: fp,
                merchantName: merchant,
                rawDescription: raw,
                occurredAt: date,
                amountCents: cents,
                direction: direction,
                category: category,
                classificationConfidence: confidence,
                status: status,
                kind: kind,
                isRecurring: isRecurring,
                paymentRail: rail,
                source: .demoSynthetic,
                userNote: note,
                excludeFromBudget: exclude,
                linkedOriginalTransactionId: linkedId,
                splits: [],
                calculationVersion: FinancialCalculationEngine.currentCalculationVersion,
                updatedAt: date
            )
        }

        let transactions: [TransactionRecord] = [
            // Today's transactions (Day 0)
            makeTx(
                accountId: everydayAccountId,
                dayOffset: 0,
                hour: 8,
                merchant: "Single O Surry Hills",
                raw: "VISA DEBIT PURCHASE SINGLE O SURRY HILLS NSW",
                cents: 1_150, // $11.50
                category: .cafesAndTakeaway,
                rail: "Apple Pay / eftpos"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: 0,
                hour: 9,
                merchant: "Transport for NSW (Opal)",
                raw: "TRANSPORT FOR NSW OPAL SYDNEY AU",
                cents: 960, // $9.60
                category: .publicTransport,
                rail: "Contactless Card"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: 0,
                hour: 13,
                merchant: "Woolworths Metro",
                raw: "EFTPOS DEBIT WOOLWORTHS METRO MARRICKVILLE",
                cents: 3_640, // $36.40
                category: .groceries,
                status: .pending,
                rail: "eftpos"
            ),

            // Yesterday & earlier in the current fortnight (Days -1 to -8)
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -1,
                hour: 18,
                merchant: "Coles Supermarkets",
                raw: "EFTPOS DEBIT COLES 0742 SURRY HILLS",
                cents: 14_280, // $142.80
                category: .groceries,
                rail: "eftpos"
            ),
            makeTx(
                accountId: creditCardAccountId,
                dayOffset: -1,
                hour: 20,
                merchant: "Uber Eats AU",
                raw: "UBER *EATS HELP.UBER.COM SYDNEY",
                cents: 4_890, // $48.90
                category: .restaurantsAndDelivery,
                kind: .creditCardPurchase,
                rail: "Visa Credit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -2,
                hour: 10,
                merchant: "Medicare Australia Rebate",
                raw: "DIRECT CREDIT MEDICARE BENEFIT REBATE",
                cents: 4_285, // +$42.85 refund offsetting healthcare spend
                direction: .credit,
                category: .healthcareMedicare,
                kind: .refund,
                rail: "Direct Credit",
                note: "Medicare rebate for GP consultation",
                linkedId: medicalTxId
            ),
            makeTx(
                id: medicalTxId,
                accountId: everydayAccountId,
                dayOffset: -3,
                hour: 11,
                merchant: "Crown St Medical Centre",
                raw: "EFTPOS DEBIT CROWN ST MEDICAL CENTRE SURRY HILLS",
                cents: 9_500, // $95.00
                category: .healthcareMedicare,
                rail: "eftpos"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -3,
                hour: 15,
                merchant: "UNCLASSIFIED MERCHANT #409",
                raw: "EFTPOS DEBIT SQ *MKT STALL 409 SYDNEY",
                cents: 2_850, // $28.50 — intentionally low confidence to demonstrate uncertainty UI
                category: .cashAndUnclassified,
                confidence: 0.42,
                rail: "eftpos",
                note: "Needs category review"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -4,
                hour: 9,
                merchant: "Aussie Broadband",
                raw: "DIRECT DEBIT AUSSIE BROADBAND NBN",
                cents: 8_900, // $89.00
                category: .utilitiesAndInternet,
                isRecurring: true,
                rail: "Direct Debit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -4,
                hour: 14,
                merchant: "Ampol Foodary Alexandria",
                raw: "VISA DEBIT AMPOL ALEXANDRIA 2015",
                cents: 7_420, // $74.20
                category: .fuelTollsVehicle,
                rail: "Visa Debit"
            ),
            makeTx(
                accountId: creditCardAccountId,
                dayOffset: -5,
                hour: 16,
                merchant: "Bunnings Warehouse",
                raw: "BUNNINGS 7120 ALEXANDRIA NSW",
                cents: 8_450, // $84.50
                category: .shoppingRetail,
                kind: .creditCardPurchase,
                rail: "Visa Credit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -6,
                hour: 12,
                merchant: "Credit Card Bill Repayment",
                raw: "BPAY CREDIT CARD REPAYMENT TASMAN VISA",
                cents: 45_000, // $450.00 — NOT counted as spending twice!
                category: .creditCardRepayment,
                kind: .creditCardRepayment,
                rail: "BPAY",
                note: "Monthly statement payment — excluded from consumption"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -7,
                hour: 9,
                merchant: "Inner West Property Mgmt (Rent)",
                raw: "OSKO PAYMENT RENT 42/18 MYRTLE ST MARRICKVILLE",
                cents: 92_000, // $920.00
                category: .rentAndMortgage,
                isRecurring: true,
                rail: "Osko / PayID"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -7,
                hour: 10,
                merchant: "Own Account Savings Transfer",
                raw: "INTERNAL TRANSFER TO SAVINGS 9012",
                cents: 50_000, // $500.00 — NOT counted as spending!
                category: .ownAccountTransfer,
                kind: .ownAccountTransfer,
                rail: "Internal Transfer",
                note: "Fortnightly payday transfer to Home Deposit Saver"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -8,
                hour: 8,
                merchant: "Atlassian AU Payroll (Demo)",
                raw: "DIRECT CREDIT SALARY PAYROLL FORTNIGHTLY",
                cents: 325_000, // +$3,250.00
                direction: .credit,
                category: .salaryWagesIncome,
                kind: .income,
                isRecurring: true,
                rail: "Direct Credit"
            ),

            // Previous fortnight transactions (Days -10 to -22) for recurring detection & historical charts
            makeTx(
                accountId: creditCardAccountId,
                dayOffset: -10,
                hour: 8,
                merchant: "Netflix Australia",
                raw: "NETFLIX.COM MELBOURNE AUS",
                cents: 2_599, // $25.99
                category: .streamingSubscriptions,
                kind: .creditCardPurchase,
                isRecurring: true,
                rail: "Visa Credit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -11,
                hour: 7,
                merchant: "Anytime Fitness Newtown",
                raw: "DIRECT DEBIT ANYTIME FITNESS NEWTOWN",
                cents: 4_290, // $42.90
                category: .gymFitness,
                isRecurring: true,
                rail: "Direct Debit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -12,
                hour: 17,
                merchant: "Woolworths Marrickville",
                raw: "EFTPOS DEBIT WOOLWORTHS 1104 MARRICKVILLE",
                cents: 16_840, // $168.40
                category: .groceries
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -14,
                hour: 11,
                merchant: "Origin Energy Electricity",
                raw: "BPAY ORIGIN ENERGY ELECTRICITY BILL",
                cents: 18_600, // $186.00
                category: .utilitiesAndInternet,
                isRecurring: true,
                rail: "BPAY"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -16,
                hour: 13,
                merchant: "Telstra Mobile",
                raw: "DIRECT DEBIT TELSTRA MOBILE PLAN",
                cents: 6_500, // $65.00
                category: .mobilePhone,
                isRecurring: true,
                rail: "Direct Debit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -18,
                hour: 19,
                merchant: "Medibank Private Health",
                raw: "DIRECT DEBIT MEDIBANK PRIVATE",
                cents: 10_420, // $104.20
                category: .insurance,
                isRecurring: true,
                rail: "Direct Debit"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -21,
                hour: 9,
                merchant: "Inner West Property Mgmt (Rent)",
                raw: "OSKO PAYMENT RENT 42/18 MYRTLE ST MARRICKVILLE",
                cents: 92_000, // $920.00
                category: .rentAndMortgage,
                isRecurring: true,
                rail: "Osko / PayID"
            ),
            makeTx(
                accountId: everydayAccountId,
                dayOffset: -22,
                hour: 8,
                merchant: "Atlassian AU Payroll (Demo)",
                raw: "DIRECT CREDIT SALARY PAYROLL FORTNIGHTLY",
                cents: 325_000, // +$3,250.00
                direction: .credit,
                category: .salaryWagesIncome,
                kind: .income,
                isRecurring: true,
                rail: "Direct Credit"
            )
        ]

        // Initial Recurring Bills & Subscriptions (both confirmed and predicted)
        let recurringPredictions: [RecurringPaymentPrediction] = [
            RecurringPaymentPrediction(
                id: UUID(),
                tenantId: demoTenantId,
                merchantName: "Anytime Fitness Newtown",
                category: .gymFitness,
                expectedAmountCents: 4_290,
                frequency: .fortnightly,
                nextExpectedDate: daysOffset(3),
                lastPaymentDate: daysOffset(-11),
                confidence: .confirmedSchedule,
                isConfirmedByUser: true,
                isDismissed: false,
                paymentRail: "Direct Debit",
                linkedTransactionIds: []
            ),
            RecurringPaymentPrediction(
                id: UUID(),
                tenantId: demoTenantId,
                merchantName: "Inner West Property Mgmt (Rent)",
                category: .rentAndMortgage,
                expectedAmountCents: 92_000,
                frequency: .fortnightly,
                nextExpectedDate: daysOffset(5),
                lastPaymentDate: daysOffset(-7),
                confidence: .confirmedSchedule,
                isConfirmedByUser: true,
                isDismissed: false,
                paymentRail: "Osko / PayID",
                linkedTransactionIds: []
            ),
            RecurringPaymentPrediction(
                id: UUID(),
                tenantId: demoTenantId,
                merchantName: "Telstra Mobile",
                category: .mobilePhone,
                expectedAmountCents: 6_500,
                frequency: .monthly,
                nextExpectedDate: daysOffset(14),
                lastPaymentDate: daysOffset(-16),
                confidence: .high,
                isConfirmedByUser: false,
                isDismissed: false,
                paymentRail: "Direct Debit",
                linkedTransactionIds: []
            ),
            RecurringPaymentPrediction(
                id: UUID(),
                tenantId: demoTenantId,
                merchantName: "Netflix Australia",
                category: .streamingSubscriptions,
                expectedAmountCents: 2_599,
                frequency: .monthly,
                nextExpectedDate: daysOffset(20),
                lastPaymentDate: daysOffset(-10),
                confidence: .high,
                isConfirmedByUser: false,
                isDismissed: false,
                paymentRail: "Visa Credit",
                linkedTransactionIds: []
            )
        ]

        // Savings Goals
        let savingsGoals: [SavingsGoal] = [
            SavingsGoal(
                id: UUID(),
                tenantId: demoTenantId,
                name: "3-Month Emergency Buffer",
                iconName: "lifepreserver.fill",
                targetAmountCents: 1_500_000, // $15,000.00
                currentSavedCents: 1_125_000, // $11,250.00 (75%)
                targetDate: daysOffset(140),
                linkedAccountId: savingsAccountId,
                contributions: [
                    SavingsContribution(id: UUID(), date: daysOffset(-7), amountCents: 35_000, note: "Fortnightly auto-transfer"),
                    SavingsContribution(id: UUID(), date: daysOffset(-21), amountCents: 35_000, note: "Fortnightly auto-transfer")
                ],
                assumptionsNote: "Tracked against recorded contributions. Does not assume variable bonus interest rates.",
                createdAt: daysOffset(-90)
            ),
            SavingsGoal(
                id: UUID(),
                tenantId: demoTenantId,
                name: "Tasmania Summer Holiday",
                iconName: "airplane.departure",
                targetAmountCents: 350_000, // $3,500.00
                currentSavedCents: 210_000, // $2,100.00 (60%)
                targetDate: daysOffset(75),
                linkedAccountId: savingsAccountId,
                contributions: [
                    SavingsContribution(id: UUID(), date: daysOffset(-7), amountCents: 15_000, note: "Payday holiday fund top-up")
                ],
                assumptionsNote: "Suggested $150.00 per fortnight reaches $3,500.00 before target date.",
                createdAt: daysOffset(-60)
            ),
            SavingsGoal(
                id: UUID(),
                tenantId: demoTenantId,
                name: "First Home Deposit (FHSS / Offset)",
                iconName: "house.lodge.fill",
                targetAmountCents: 8_000_000, // $80,000.00
                currentSavedCents: 510_000,   // $5,100.00
                targetDate: daysOffset(730),
                linkedAccountId: savingsAccountId,
                contributions: [],
                assumptionsNote: "Goal tracking only; does not represent FHSS tax determination advice.",
                createdAt: daysOffset(-120)
            )
        ]

        // In-App Notifications
        let notifications: [AppNotification] = [
            AppNotification(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Upcoming Bills Before Payday",
                body: "Anytime Fitness ($42.90) and Fortnightly Rent ($920.00) are scheduled before your next payday.",
                categoryTag: "Bills",
                createdAt: daysOffset(0, hour: 8, minute: 30),
                isRead: false
            ),
            AppNotification(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Medicare Rebate Matched",
                body: "A $42.85 Medicare rebate was automatically offset against your Healthcare spending.",
                categoryTag: "Reconciliation",
                createdAt: daysOffset(-2, hour: 10, minute: 15),
                isRead: false
            ),
            AppNotification(
                id: UUID(),
                tenantId: demoTenantId,
                title: "Transaction Needs Review",
                body: "SQ *MKT STALL 409 ($28.50) had low merchant confidence and was placed in Unclassified.",
                categoryTag: "Categorisation",
                createdAt: daysOffset(-3, hour: 15, minute: 30),
                isRead: true
            )
        ]

        let auditEvents: [AuditEvent] = [
            AuditEvent(
                id: UUID(),
                tenantId: demoTenantId,
                action: "DEMO_SEED_INITIALISED",
                entityType: "TenantWorkspace",
                entityId: demoTenantId,
                summary: "Initialised synthetic Australian financial dataset (AUD, Australia/Sydney).",
                createdAt: daysOffset(-1)
            )
        ]

        return TenantWorkspaceSnapshot(
            tenantId: demoTenantId,
            profile: profile,
            accounts: accounts,
            consentRecords: [demoConsent],
            transactions: transactions,
            merchantRules: [],
            fixedCommitments: fixedCommitments,
            categoryBudgets: categoryBudgets,
            recurringPredictions: recurringPredictions,
            savingsGoals: savingsGoals,
            notificationPreferences: NotificationPreferences(
                dailySummaryEnabled: true,
                dailySummaryHour: 19,
                budgetThresholdAlertsEnabled: true,
                upcomingBillRemindersEnabled: true,
                paydayRemindersEnabled: true,
                recurringChangeAlertsEnabled: true,
                unusualSpendingAlertsEnabled: true,
                hideExactAmountsInPreviews: false
            ),
            notifications: notifications,
            importJobs: [],
            auditEvents: auditEvents,
            processedIdempotencyKeys: []
        )
    }

    // MARK: - Sample Australian Bank CSV Statement for Interactive Testing

    public static func sampleAustralianBankCSV(referenceDate: Date = Date()) -> String {
        let cal = AustralianDateHelper.calendar(for: AustralianTimeZone.sydney.rawValue)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_AU")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "dd/MM/yyyy"

        let d0 = fmt.string(from: referenceDate)
        let d1 = fmt.string(from: cal.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate)
        let d2 = fmt.string(from: cal.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate)
        let d3 = fmt.string(from: cal.date(byAdding: .day, value: -3, to: referenceDate) ?? referenceDate)

        // Note: Includes two legitimate $4.80 coffee/Opal taps on the same day to demonstrate non-destructive duplicate handling,
        // plus one malformed row to demonstrate rejected-row review.
        return """
        Date,Description,Amount
        \(d0),"EFTPOS DEBIT CAMPOS COFFEE NEWTOWN NSW",-5.80
        \(d0),"EFTPOS DEBIT CAMPOS COFFEE NEWTOWN NSW",-5.80
        \(d1),"VISA DEBIT HARRIS FARM MARKETS BROADWAY",-64.20
        \(d1),"TRANSPORT FOR NSW OPAL TOPUP",-20.00
        \(d2),"DIRECT DEBIT SYDNEY WATER QUARTERLY",-148.50
        \(d2),"DIRECT CREDIT ATO TAX REFUND",310.00
        \(d3),"EFTPOS DEBIT CHEMIST WAREHOUSE PITT ST",-29.95
        INVALID_DATE_ROW,"CORRUPTED STATEMENT LINE",NOT_A_NUMBER
        """
    }
}
