import Foundation

public enum FinancialCalculationEngine {
    public static let currentCalculationVersion: Int = 2

    // MARK: - 1. Active Period Bounds Calculation

    /// Computes the start and end of the active budget period in the user's configured Australian time zone.
    public static func currentPeriodBounds(
        referenceDate: Date,
        profile: UserProfile
    ) -> (start: Date, end: Date, totalDays: Int, elapsedDays: Int, remainingDays: Int) {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let startOfToday = cal.startOfDay(for: referenceDate)

        switch profile.preferredBudgetingMethod {
        case .monthlyFlexible:
            let comps = cal.dateComponents([.year, .month], from: startOfToday)
            let startOfMonth = cal.date(from: comps) ?? startOfToday
            let range = cal.range(of: .day, in: .month, for: startOfMonth) ?? 1..<31
            let totalDays = range.count
            let endOfMonth = cal.date(byAdding: .day, value: totalDays - 1, to: startOfMonth) ?? startOfToday
            let elapsed = max(0, cal.dateComponents([.day], from: startOfMonth, to: startOfToday).day ?? 0)
            let remaining = max(1, totalDays - elapsed)
            return (startOfMonth, endOfMonth, totalDays, elapsed, remaining)

        default:
            let nominalDays = max(1, profile.payFrequency.nominalPeriodDays)
            let anchorNextPay = cal.startOfDay(for: profile.nextPayDate)

            // Walk forward or backward from anchorNextPay in steps of nominalDays so referenceDate falls inside [periodStart, periodEnd]
            var periodEndExclusive = anchorNextPay
            while periodEndExclusive <= startOfToday {
                periodEndExclusive = cal.date(byAdding: .day, value: nominalDays, to: periodEndExclusive) ?? periodEndExclusive.addingTimeInterval(Double(nominalDays) * 86400)
            }
            while let prev = cal.date(byAdding: .day, value: -nominalDays, to: periodEndExclusive), prev > startOfToday {
                periodEndExclusive = prev
            }

            let periodStart = cal.date(byAdding: .day, value: -nominalDays, to: periodEndExclusive) ?? startOfToday
            let periodEndInclusive = cal.date(byAdding: .day, value: -1, to: periodEndExclusive) ?? startOfToday
            let totalDays = max(1, cal.dateComponents([.day], from: periodStart, to: periodEndExclusive).day ?? nominalDays)
            let elapsed = min(totalDays - 1, max(0, cal.dateComponents([.day], from: periodStart, to: startOfToday).day ?? 0))
            let remaining = max(1, totalDays - elapsed)
            return (periodStart, periodEndInclusive, totalDays, elapsed, remaining)
        }
    }

    // MARK: - 2. Transaction Eligibility & Net Spend Rules

    /// Determines whether a transaction represents net flexible spending, fixed bill payment, income, or non-consumption transfer.
    /// - Own-account transfers (`ownAccountTransfer`) and credit card bill repayments (`creditCardRepayment`) NEVER count as consumption.
    /// - Credit card purchases (`creditCardPurchase`) count as consumption when the purchase is made.
    /// - Refunds (`refund`) and reversals (`reversal`) offset spending in their category rather than inflating income.
    public static func netSpendContributionCents(
        for transaction: TransactionRecord,
        categoryFilter: AustralianCategory? = nil,
        includeFixedCategories: Bool = true
    ) -> MoneyCents {
        guard !transaction.excludeFromBudget else { return 0 }
        guard transaction.status != .reversed else { return 0 }

        switch transaction.kind {
        case .ownAccountTransfer, .creditCardRepayment, .income:
            return 0
        case .refund, .reversal:
            if !transaction.splits.isEmpty {
                return transaction.splits.reduce(0) { acc, split in
                    guard !split.excludeFromBudget else { return acc }
                    if let filter = categoryFilter, split.category != filter { return acc }
                    if !includeFixedCategories && split.category.isDefaultFixedCommitment { return acc }
                    return acc - split.amountCents
                }
            }
            if let filter = categoryFilter, transaction.category != filter { return 0 }
            if !includeFixedCategories && transaction.category.isDefaultFixedCommitment { return 0 }
            return -transaction.amountCents

        case .expense, .creditCardPurchase, .cashWithdrawal, .feeOrInterest:
            let sign: MoneyCents = (transaction.direction == .debit) ? 1 : -1
            if !transaction.splits.isEmpty {
                return transaction.splits.reduce(0) { acc, split in
                    guard !split.excludeFromBudget else { return acc }
                    if let filter = categoryFilter, split.category != filter { return acc }
                    if !includeFixedCategories && split.category.isDefaultFixedCommitment { return acc }
                    return acc + (split.amountCents * sign)
                }
            }
            if let filter = categoryFilter, transaction.category != filter { return 0 }
            if !includeFixedCategories && transaction.category.isDefaultFixedCommitment { return 0 }
            return transaction.amountCents * sign
        }
    }

    // MARK: - 3. Daily Safe-to-Spend & Period Budget Calculation

    public static func calculateDailyAllowanceSummary(
        referenceDate: Date,
        profile: UserProfile,
        accounts: [FinancialAccount],
        transactions: [TransactionRecord],
        fixedCommitments: [FixedCommitment],
        categoryBudgets: [CategoryBudget]
    ) -> DailyAllowanceSummary {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let bounds = currentPeriodBounds(referenceDate: referenceDate, profile: profile)
        let startOfToday = cal.startOfDay(for: referenceDate)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate

        // 1. Account balances (clearly separated from budget figures)
        let activeAccounts = accounts.filter { $0.connectionStatus != .disconnected }
        let everydayAvailableCents = activeAccounts
            .filter { $0.accountType == .everydayTransaction }
            .reduce(MoneyCents(0)) { $0 + $1.availableBalanceCents }

        let totalLiquidCashCents = activeAccounts
            .filter { $0.accountType.isAssetAccount && $0.includeInSafeToSpendCash }
            .reduce(MoneyCents(0)) { $0 + $1.availableBalanceCents }

        let totalDebtCents = activeAccounts
            .filter { !$0.accountType.isAssetAccount }
            .reduce(MoneyCents(0)) { $0 + abs($1.currentBalanceCents) }

        // 2. Normalize income, fixed commitments, and savings to the active period length
        let periodDays = bounds.totalDays
        let userCycleDays = max(1, profile.payFrequency.nominalPeriodDays)

        let periodIncomeCents: MoneyCents = {
            if periodDays == userCycleDays {
                return profile.typicalTakeHomePayCents
            }
            return (profile.typicalTakeHomePayCents * Int64(periodDays)) / Int64(userCycleDays)
        }()

        let periodSavingsCents: MoneyCents = {
            if periodDays == userCycleDays {
                return profile.savingsTargetPerPeriodCents
            }
            return (profile.savingsTargetPerPeriodCents * Int64(periodDays)) / Int64(userCycleDays)
        }()

        let confirmedFixedCents: MoneyCents = fixedCommitments
            .filter { $0.isConfirmed }
            .reduce(0) { sum, commitment in
                let commitDays = max(1, commitment.frequency.nominalPeriodDays)
                if commitDays == periodDays {
                    return sum + commitment.amountCents
                }
                return sum + ((commitment.amountCents * Int64(periodDays)) / Int64(commitDays))
            }

        // Filter transactions occurring within the active period [bounds.start, endOfPeriod]
        let periodEndExclusive = cal.date(byAdding: .day, value: 1, to: bounds.end) ?? bounds.end
        let periodTransactions = transactions.filter { tx in
            tx.occurredAt >= bounds.start && tx.occurredAt < periodEndExclusive
        }

        // Fixed bills already paid during this period (so we never double-subtract paid fixed bills!)
        let paidFixedInPeriodCents: MoneyCents = periodTransactions.reduce(0) { sum, tx in
            guard !tx.excludeFromBudget, tx.status != .reversed else { return sum }
            guard tx.category.isDefaultFixedCommitment, tx.direction == .debit else { return sum }
            if tx.kind == .ownAccountTransfer || tx.kind == .creditCardRepayment { return sum }
            return sum + tx.amountCents
        }

        let effectiveTotalFixedForPeriodCents = max(confirmedFixedCents, paidFixedInPeriodCents)
        let unpaidFixedRemainingCents = max(0, confirmedFixedCents - paidFixedInPeriodCents)
        let availableCashAfterCommitmentsCents = everydayAvailableCents - unpaidFixedRemainingCents

        // 3. Determine total flexible budget for the period according to the user's selected BudgetingMethod
        let derivedPoolCents = max(0, periodIncomeCents - effectiveTotalFixedForPeriodCents - periodSavingsCents)
        let totalFlexibleBudgetCents: MoneyCents = {
            switch profile.preferredBudgetingMethod {
            case .custom:
                if let customCap = profile.customFlexibleCapCents, customCap > 0 {
                    return customCap
                }
                return derivedPoolCents
            case .categorySpecific:
                let flexibleCategorySum = categoryBudgets
                    .filter { !$0.category.isDefaultFixedCommitment }
                    .reduce(MoneyCents(0)) { $0 + $1.limitCents + ($1.rolloverEnabled ? $1.rolloverBalanceCents : 0) }
                return flexibleCategorySum > 0 ? flexibleCategorySum : derivedPoolCents
            case .simpleDailyAllowance, .monthlyFlexible, .payCycle, .savingsFirst:
                return derivedPoolCents
            }
        }()

        // Baseline daily allowance across full period
        let baselineDailyCents = totalFlexibleBudgetCents / Int64(max(1, bounds.totalDays))

        // 4. Calculate flexible spending prior to today vs today
        var spentPriorToTodayCents: MoneyCents = 0
        var spentTodayCents: MoneyCents = 0

        for tx in periodTransactions {
            let netFlexible = netSpendContributionCents(
                for: tx,
                categoryFilter: nil,
                includeFixedCategories: false
            )
            guard netFlexible != 0 else { continue }
            if tx.occurredAt >= startOfToday && tx.occurredAt < endOfToday {
                spentTodayCents += netFlexible
            } else if tx.occurredAt < startOfToday {
                spentPriorToTodayCents += netFlexible
            } else {
                spentTodayCents += netFlexible
            }
        }

        spentPriorToTodayCents = max(0, spentPriorToTodayCents)
        let totalFlexibleSpentCents = max(0, spentPriorToTodayCents + spentTodayCents)
        let remainingFlexibleForPeriodCents = totalFlexibleBudgetCents - totalFlexibleSpentCents

        // Dynamic Safe-to-Spend at the start of today:
        // Take the flexible budget remaining at the start of today and divide across remaining days (including today).
        let budgetAtStartOfTodayCents = max(0, totalFlexibleBudgetCents - spentPriorToTodayCents)
        let todaysStartingAllowanceCents = budgetAtStartOfTodayCents / Int64(max(1, bounds.remainingDays))
        let todaysRemainingAllowanceCents = todaysStartingAllowanceCents - spentTodayCents

        // Forecast end-of-period flexible spend
        let activeDaysSoFar = max(1, bounds.elapsedDays + 1)
        let dailyRunRateCents = totalFlexibleSpentCents / Int64(activeDaysSoFar)
        let forecastFlexibleCents = dailyRunRateCents * Int64(bounds.totalDays)

        let steps: [String] = [
            "1. Period Take-Home Income (\(bounds.totalDays) days): \(AustralianMoneyFormatter.format(cents: periodIncomeCents))",
            "2. Less Fixed Commitments & Bills (paid & scheduled, never double-counted): -\(AustralianMoneyFormatter.format(cents: effectiveTotalFixedForPeriodCents))",
            "3. Less Planned Savings Target: -\(AustralianMoneyFormatter.format(cents: periodSavingsCents))",
            "4. Total Flexible Budget for Period: \(AustralianMoneyFormatter.format(cents: totalFlexibleBudgetCents)) (Baseline \(AustralianMoneyFormatter.format(cents: baselineDailyCents))/day)",
            "5. Less Flexible Spending Before Today: -\(AustralianMoneyFormatter.format(cents: spentPriorToTodayCents))",
            "6. Today's Opening Safe Allowance (\(AustralianMoneyFormatter.format(cents: budgetAtStartOfTodayCents)) ÷ \(bounds.remainingDays) days left): \(AustralianMoneyFormatter.format(cents: todaysStartingAllowanceCents))",
            "7. Less Today's Eligible Flexible Spending: -\(AustralianMoneyFormatter.format(cents: spentTodayCents))",
            "8. Today's Remaining Safe-to-Spend Allowance: \(AustralianMoneyFormatter.format(cents: todaysRemainingAllowanceCents))"
        ]

        return DailyAllowanceSummary(
            periodStart: bounds.start,
            periodEnd: bounds.end,
            totalDaysInPeriod: bounds.totalDays,
            elapsedDaysInPeriod: bounds.elapsedDays,
            remainingDaysInPeriod: bounds.remainingDays,
            everydayAvailableBankBalanceCents: everydayAvailableCents,
            totalLiquidCashAcrossAccountsCents: totalLiquidCashCents,
            totalCreditCardAndDebtBalanceCents: totalDebtCents,
            periodTakeHomeIncomeCents: periodIncomeCents,
            totalFixedCommitmentsForPeriodCents: effectiveTotalFixedForPeriodCents,
            unpaidFixedCommitmentsRemainingCents: unpaidFixedRemainingCents,
            plannedSavingsForPeriodCents: periodSavingsCents,
            availableCashAfterCommitmentsCents: availableCashAfterCommitmentsCents,
            totalFlexibleBudgetForPeriodCents: totalFlexibleBudgetCents,
            baselineDailyAllowanceCents: baselineDailyCents,
            flexibleSpentPriorToTodayCents: spentPriorToTodayCents,
            flexibleSpentTodayCents: spentTodayCents,
            totalFlexibleSpentInPeriodCents: totalFlexibleSpentCents,
            remainingFlexibleBudgetForPeriodCents: remainingFlexibleForPeriodCents,
            todaysStartingAllowanceCents: todaysStartingAllowanceCents,
            todaysRemainingAllowanceCents: todaysRemainingAllowanceCents,
            forecastEndOfPeriodFlexibleSpendCents: forecastFlexibleCents,
            calculationSteps: steps,
            budgetingMethodUsed: profile.preferredBudgetingMethod,
            calculationVersion: currentCalculationVersion
        )
    }

    // MARK: - 4. Category Budget Progress Calculation

    public static func calculateCategoryBudgetsProgress(
        referenceDate: Date,
        profile: UserProfile,
        transactions: [TransactionRecord],
        categoryBudgets: [CategoryBudget]
    ) -> [CategoryBudgetProgress] {
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)
        let bounds = currentPeriodBounds(referenceDate: referenceDate, profile: profile)
        let periodEndExclusive = cal.date(byAdding: .day, value: 1, to: bounds.end) ?? bounds.end

        let periodTransactions = transactions.filter {
            $0.occurredAt >= bounds.start && $0.occurredAt < periodEndExclusive
        }

        let elapsedDays = max(1, bounds.elapsedDays + 1)

        return categoryBudgets.map { budget in
            let effectiveLimit = budget.limitCents + (budget.rolloverEnabled ? budget.rolloverBalanceCents : 0)
            var netSpent: MoneyCents = 0
            var matchingTxs: [TransactionRecord] = []

            for tx in periodTransactions {
                let contribution = netSpendContributionCents(
                    for: tx,
                    categoryFilter: budget.category,
                    includeFixedCategories: true
                )
                if contribution != 0 {
                    netSpent += contribution
                    matchingTxs.append(tx)
                }
            }

            netSpent = max(0, netSpent)
            let remaining = effectiveLimit - netSpent
            let ratio = effectiveLimit > 0 ? Double(netSpent) / Double(effectiveLimit) : 0
            let projected = (netSpent * Int64(bounds.totalDays)) / Int64(elapsedDays)

            return CategoryBudgetProgress(
                category: budget.category,
                budgetedCents: effectiveLimit,
                netSpentCents: netSpent,
                remainingCents: remaining,
                percentageUsed: ratio,
                projectedEndOfPeriodCents: projected,
                isOverBudget: netSpent > effectiveLimit,
                recentTransactions: matchingTxs.sorted { $0.occurredAt > $1.occurredAt }
            )
        }
        .sorted { $0.percentageUsed > $1.percentageUsed }
    }

    // MARK: - 5. Australian Merchant & Category Classifier

    public struct ClassificationResult: Equatable, Sendable {
        public let normalizedMerchant: String
        public let category: AustralianCategory
        public let kind: TransactionKind
        public let paymentRail: String?
        public let confidence: Double
    }

    /// Classifies an Australian transaction description using user merchant rules first, then curated Australian merchant patterns.
    /// Never classifies purely from an amount or ambiguous generic text; returns low confidence (< 0.5) when uncertain.
    public static func classifyAustralianTransaction(
        rawDescription: String,
        direction: TransactionDirection,
        isCreditCardAccount: Bool,
        userMerchantRules: [MerchantRule] = []
    ) -> ClassificationResult {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        // Detect Australian payment rail from description
        let detectedRail: String? = {
            if upper.contains("OSKO") || upper.contains("PAYID") || upper.contains("NPP") {
                return "Osko / PayID"
            } else if upper.contains("BPAY") {
                return "BPAY"
            } else if upper.contains("DIRECT DEBIT") || upper.contains("DDR") {
                return "Direct Debit"
            } else if upper.contains("EFTPOS") || upper.contains("VISA") || upper.contains("MASTERCARD") || upper.contains("APPLE PAY") {
                return "eftpos / Card"
            }
            return nil
        }()

        // 1. Check user-defined merchant rules first
        for rule in userMerchantRules {
            if upper.localizedCaseInsensitiveContains(rule.matchSubstring) {
                let kind: TransactionKind = (direction == .credit) ? .income : (isCreditCardAccount ? .creditCardPurchase : .expense)
                return ClassificationResult(
                    normalizedMerchant: rule.normalizedMerchantName,
                    category: rule.assignedCategory,
                    kind: kind,
                    paymentRail: detectedRail,
                    confidence: 0.98
                )
            }
        }

        // 2. Check internal transfers & credit card repayments
        if upper.contains("INTERNAL TRANSFER") || upper.contains("TRANSFER TO OFFSET") || upper.contains("TRANSFER TO SAVINGS") || upper.contains("TRANSFER FROM SAVINGS") || upper.contains("OWN ACCOUNT") {
            return ClassificationResult(
                normalizedMerchant: "Own Account Transfer",
                category: .ownAccountTransfer,
                kind: .ownAccountTransfer,
                paymentRail: detectedRail ?? "Internal Transfer",
                confidence: 0.96
            )
        }

        if upper.contains("CREDIT CARD REPAYMENT") || upper.contains("CC REPAYMENT") || upper.contains("CARD AUTOPAY") {
            return ClassificationResult(
                normalizedMerchant: "Credit Card Repayment",
                category: .creditCardRepayment,
                kind: .creditCardRepayment,
                paymentRail: detectedRail ?? "BPAY / Internal",
                confidence: 0.96
            )
        }

        // 3. Check refunds & rebates
        if direction == .credit && (upper.contains("REFUND") || upper.contains("REBATE") || upper.contains("MEDICARE") || upper.contains("REVERSAL")) {
            let isMedicare = upper.contains("MEDICARE")
            return ClassificationResult(
                normalizedMerchant: isMedicare ? "Medicare Australia Rebate" : trimmed,
                category: isMedicare ? .healthcareMedicare : .shoppingRetail,
                kind: upper.contains("REVERSAL") ? .reversal : .refund,
                paymentRail: detectedRail,
                confidence: 0.92
            )
        }

        // 4. Check Australian income sources
        if direction == .credit {
            if upper.contains("SALARY") || upper.contains("PAYROLL") || upper.contains("WAGES") || upper.contains("PTY LTD") {
                return ClassificationResult(
                    normalizedMerchant: "Employer Payroll",
                    category: .salaryWagesIncome,
                    kind: .income,
                    paymentRail: detectedRail ?? "Direct Credit",
                    confidence: 0.94
                )
            }
            if upper.contains("SERVICES AUSTRALIA") || upper.contains("CENTRELINK") || upper.contains("FAMILY TAX") {
                return ClassificationResult(
                    normalizedMerchant: "Services Australia",
                    category: .governmentPayments,
                    kind: .income,
                    paymentRail: "Direct Credit",
                    confidence: 0.95
                )
            }
        }

        let defaultPurchaseKind: TransactionKind = isCreditCardAccount ? .creditCardPurchase : .expense

        // 5. Curated Australian merchants & institutions
        let rules: [(keywords: [String], merchant: String, category: AustralianCategory, confidence: Double)] = [
            (["WOOLWORTHS", "METRO WOOLWORTHS"], "Woolworths", .groceries, 0.96),
            (["COLES", "COLES SUPERMARKET"], "Coles", .groceries, 0.96),
            (["ALDI STORES", "ALDI "], "ALDI", .groceries, 0.95),
            (["IGA ", "HARRIS FARM"], "Harris Farm / IGA", .groceries, 0.93),
            (["TRANSPORT FOR NSW", "OPAL "], "Transport for NSW (Opal)", .publicTransport, 0.97),
            (["MYKI", "PTV "], "PTV Myki", .publicTransport, 0.97),
            (["TRANSLINK"], "Translink QLD", .publicTransport, 0.96),
            (["LINKT", "E-TOLL", "ROAM EXPRESS"], "Linkt Tolls", .fuelTollsVehicle, 0.94),
            (["AMPOL", "CALTEX", "BP ", "SHELL COLES EXPRESS", "7-ELEVEN FUEL"], "Service Station / Fuel", .fuelTollsVehicle, 0.90),
            (["UBER *TRIP", "DIDI "], "Rideshare (Uber / DiDi)", .fuelTollsVehicle, 0.89),
            (["UBER *EATS", "MENULOG", "DOORDASH"], "Food Delivery", .restaurantsAndDelivery, 0.93),
            (["SINGLE O", "CAMPOS", "PROUD MARY", "CAFE", "COFFEE", "ESPRESSO", "BAKERY"], "Local Cafe & Coffee", .cafesAndTakeaway, 0.88),
            (["ORIGIN ENERGY", "AGL ", "ENERGYAUSTRALIA", "RED ENERGY", "SYDNEY WATER", "YARRA VALLEY WATER", "AUSSIE BROADBAND", "NBN "], "Utilities & Internet", .utilitiesAndInternet, 0.95),
            (["TELSTRA", "OPTUS", "VODAFONE", "BOOST MOBILE", "BELONG"], "Mobile Provider", .mobilePhone, 0.95),
            (["MEDIBANK", "BUPA", "HCF ", "NIB ", "NRMA INSURANCE", "AAMI", "ALLIANZ"], "Insurance Provider", .insurance, 0.94),
            (["CHEMIST WAREHOUSE", "PRICELINE PHARMACY", "TERRYWHITE", "MEDICAL CENTRE", "DENTAL"], "Pharmacy & Healthcare", .healthcareMedicare, 0.92),
            (["ATO HECS", "HELP REPAYMENT"], "ATO HECS-HELP", .hecsHelp, 0.95),
            (["COUNCIL RATES", "STRATA"], "Council Rates & Strata", .councilRatesStrata, 0.93),
            (["ANYTIME FITNESS", "FITNESS FIRST", "F45 ", "JETTS", "VIRGIN ACTIVE"], "Gym & Fitness", .gymFitness, 0.94),
            (["NETFLIX", "SPOTIFY", "APPLE.COM/BILL", "STAN.COM.AU", "KAYO SPORTS", "BINGE"], "Streaming Subscription", .streamingSubscriptions, 0.95),
            (["AFTERPAY", "ZIP PAY", "ZIP MONEY", "PAYPAL PAY IN 4"], "Buy Now, Pay Later", .buyNowPayLater, 0.95),
            (["BUNNINGS", "KMART", "TARGET AU", "JB HI-FI", "OFFICEWORKS", "MYER", "DAVID JONES", "THE ICONIC", "MECCA"], "Retail Shopping", .shoppingRetail, 0.91),
            (["QANTAS", "VIRGIN AUSTRALIA", "JETSTAR", "AIRBNB", "BOOKING.COM"], "Domestic Travel & Stays", .domesticTravelHolidays, 0.92),
            (["RENT ", "REAL ESTATE", "PROPERTY MGMT", "MORTGAGE REPAYMENT"], "Rent / Mortgage", .rentAndMortgage, 0.94),
            (["AUSTRALIANSuper", "HOSTPLUS", "ART SUPER", "UNISUPER", "AWARE SUPER"], "Superannuation", .superannuation, 0.94),
            (["ATM WITHDRAWAL", "CASH OUT"], "ATM / Cash Withdrawal", .cashAndUnclassified, 0.90)
        ]

        for entry in rules {
            for kw in entry.keywords where upper.contains(kw) {
                let kind: TransactionKind = (entry.category == .cashAndUnclassified) ? .cashWithdrawal : defaultPurchaseKind
                return ClassificationResult(
                    normalizedMerchant: entry.merchant == "Retail Shopping" || entry.merchant == "Local Cafe & Coffee" ? cleanMerchantDisplayName(trimmed) : entry.merchant,
                    category: entry.category,
                    kind: kind,
                    paymentRail: detectedRail,
                    confidence: entry.confidence
                )
            }
        }

        // 6. Ambiguous / unknown merchant — do NOT guess blindly; flag low confidence (< 0.70)
        return ClassificationResult(
            normalizedMerchant: cleanMerchantDisplayName(trimmed.isEmpty ? "Unclassified Transaction" : trimmed),
            category: direction == .credit ? .salaryWagesIncome : .cashAndUnclassified,
            kind: direction == .credit ? .income : defaultPurchaseKind,
            paymentRail: detectedRail,
            confidence: 0.40
        )
    }

    private static func cleanMerchantDisplayName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "VISA DEBIT PURCHASE ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "EFTPOS DEBIT ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "DIRECT DEBIT ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? raw : stripped
    }

    // MARK: - 6. Recurring Bills & Subscriptions Predictor

    public static func detectRecurringPayments(
        tenantId: String,
        transactions: [TransactionRecord],
        existingPredictions: [RecurringPaymentPrediction]
    ) -> [RecurringPaymentPrediction] {
        let expenseTxs = transactions.filter {
            $0.direction == .debit && $0.kind != .ownAccountTransfer && $0.kind != .creditCardRepayment && $0.status != .reversed
        }

        let grouped = Dictionary(grouping: expenseTxs) { $0.merchantName.lowercased() }
        var detected: [RecurringPaymentPrediction] = []

        for (_, group) in grouped {
            let sorted = group.sorted { $0.occurredAt < $1.occurredAt }
            guard let latest = sorted.last else { continue }

            // Check if already tracked in existingPredictions
            if let existing = existingPredictions.first(where: { $0.merchantName.caseInsensitiveCompare(latest.merchantName) == .orderedSame }) {
                var updated = existing
                updated.lastPaymentDate = latest.occurredAt
                updated.expectedAmountCents = latest.amountCents
                let linkedIds = Array(Set(existing.linkedTransactionIds + sorted.map(\.id)))
                updated.linkedTransactionIds = linkedIds
                detected.append(updated)
                continue
            }

            // Require at least 2 occurrences or an explicit isRecurring flag
            guard sorted.count >= 2 || latest.isRecurring else { continue }

            var inferredFrequency: RecurringFrequency = .monthly
            var confidence: PredictionConfidence = .medium

            if sorted.count >= 2 {
                let prev = sorted[sorted.count - 2]
                let dayDiff = max(1, Int(round(latest.occurredAt.timeIntervalSince(prev.occurredAt) / 86400.0)))
                if (5...9).contains(dayDiff) {
                    inferredFrequency = .weekly
                    confidence = .high
                } else if (12...16).contains(dayDiff) {
                    inferredFrequency = .fortnightly
                    confidence = .high
                } else if (26...35).contains(dayDiff) {
                    inferredFrequency = .monthly
                    confidence = .high
                } else if (80...100).contains(dayDiff) {
                    inferredFrequency = .quarterly
                    confidence = .medium
                } else {
                    confidence = .low
                }
            }

            let nextDate = Calendar.current.date(
                byAdding: .day,
                value: inferredFrequency.approximateDays,
                to: latest.occurredAt
            ) ?? latest.occurredAt.addingTimeInterval(Double(inferredFrequency.approximateDays) * 86400)

            detected.append(
                RecurringPaymentPrediction(
                    id: UUID(),
                    tenantId: tenantId,
                    merchantName: latest.merchantName,
                    category: latest.category,
                    expectedAmountCents: latest.amountCents,
                    frequency: inferredFrequency,
                    nextExpectedDate: nextDate,
                    lastPaymentDate: latest.occurredAt,
                    confidence: confidence,
                    isConfirmedByUser: false,
                    isDismissed: false,
                    paymentRail: latest.paymentRail ?? "Card / Direct Debit",
                    linkedTransactionIds: sorted.map(\.id)
                )
            )
        }

        return detected
            .filter { !$0.isDismissed }
            .sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }

    // MARK: - 7. Deterministic Insights Engine

    public static func generateDeterministicInsights(
        referenceDate: Date,
        profile: UserProfile,
        summary: DailyAllowanceSummary,
        transactions: [TransactionRecord],
        recurringBills: [RecurringPaymentPrediction],
        categoryProgress: [CategoryBudgetProgress],
        savingsGoals: [SavingsGoal]
    ) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []
        let cal = AustralianDateHelper.calendar(for: profile.timeZoneId)

        // Insight 1: Upcoming bills due before next payday
        let billsBeforePayday = recurringBills.filter { bill in
            !bill.isDismissed && bill.nextExpectedDate >= cal.startOfDay(for: referenceDate) && bill.nextExpectedDate <= profile.nextPayDate
        }
        if !billsBeforePayday.isEmpty {
            let totalDueCents = billsBeforePayday.reduce(MoneyCents(0)) { $0 + $1.expectedAmountCents }
            let names = billsBeforePayday.prefix(3).map(\.merchantName).joined(separator: ", ")
            let linkedIds = billsBeforePayday.flatMap(\.linkedTransactionIds)
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "You have \(billsBeforePayday.count) recurring payment\(billsBeforePayday.count == 1 ? "" : "s") due before payday",
                    summary: "Upcoming commitments (\(names)) total \(AustralianMoneyFormatter.format(cents: totalDueCents)) before \(AustralianDateHelper.formatShortDate(profile.nextPayDate, timeZoneId: profile.timeZoneId)).",
                    calculationDetail: "Sum of \(billsBeforePayday.count) confirmed/predicted bills falling between today and your configured next pay date.",
                    actionableRecommendation: "Your daily allowance already reserves confirmed fixed commitments, so your Everyday Account only needs \(AustralianMoneyFormatter.format(cents: totalDueCents)) ready for direct debits.",
                    severity: .headsUp,
                    relatedCategory: billsBeforePayday.first?.category,
                    supportingTransactionIds: linkedIds,
                    isDeterministic: true
                )
            )
        }

        // Insight 2: Category pacing / grocery or cafe trajectory
        if let topCategory = categoryProgress.first {
            let pct = Int(round(topCategory.percentageUsed * 100))
            if topCategory.isOverBudget {
                let overBy = topCategory.netSpentCents - topCategory.budgetedCents
                insights.append(
                    FinancialInsight(
                        id: UUID(),
                        title: "\(topCategory.category.displayName) is \(AustralianMoneyFormatter.format(cents: overBy)) above your period target",
                        summary: "You've spent \(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) against a \(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents)) target this period.",
                        calculationDetail: "Net category spending (\(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) after any refunds) minus category budget (\(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents))).",
                        actionableRecommendation: "You can adjust your category limit or let your remaining daily allowance absorb the difference across the next \(summary.remainingDaysInPeriod) days.",
                        severity: .headsUp,
                        relatedCategory: topCategory.category,
                        supportingTransactionIds: topCategory.recentTransactions.map(\.id),
                        isDeterministic: true
                    )
                )
            } else if topCategory.projectedEndOfPeriodCents > topCategory.budgetedCents && pct >= 65 {
                insights.append(
                    FinancialInsight(
                        id: UUID(),
                        title: "At your current pace, you may exceed your \(topCategory.category.displayName) budget",
                        summary: "You've used \(pct)% (\(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents))) of your \(AustralianMoneyFormatter.format(cents: topCategory.budgetedCents)) budget with \(summary.remainingDaysInPeriod) days left.",
                        calculationDetail: "Current period spend \(AustralianMoneyFormatter.format(cents: topCategory.netSpentCents)) projected across \(summary.totalDaysInPeriod) days equals \(AustralianMoneyFormatter.format(cents: topCategory.projectedEndOfPeriodCents)).",
                        actionableRecommendation: "Aim to keep \(topCategory.category.displayName) under \(AustralianMoneyFormatter.format(cents: max(0, topCategory.remainingCents / Int64(max(1, summary.remainingDaysInPeriod)))))/day for the rest of the period.",
                        severity: .neutral,
                        relatedCategory: topCategory.category,
                        supportingTransactionIds: topCategory.recentTransactions.map(\.id),
                        isDeterministic: true
                    )
                )
            }
        }

        // Insight 3: Cafes & Takeaway comparison
        let cafeTxs = transactions.filter {
            ($0.category == .cafesAndTakeaway || $0.category == .restaurantsAndDelivery) &&
            $0.direction == .debit && !$0.excludeFromBudget && $0.occurredAt >= summary.periodStart
        }
        if !cafeTxs.isEmpty {
            let totalDiningCents = cafeTxs.reduce(MoneyCents(0)) { $0 + $1.amountCents }
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "Cafes, coffee & dining check-in",
                    summary: "You've spent \(AustralianMoneyFormatter.format(cents: totalDiningCents)) across \(cafeTxs.count) visits during this budget period.",
                    calculationDetail: "Average visit is \(AustralianMoneyFormatter.format(cents: totalDiningCents / Int64(max(1, cafeTxs.count)))) across \(cafeTxs.count) posted transactions.",
                    actionableRecommendation: "Tap to inspect the \(cafeTxs.count) underlying cafe and takeaway transactions.",
                    severity: .neutral,
                    relatedCategory: .cafesAndTakeaway,
                    supportingTransactionIds: cafeTxs.map(\.id),
                    isDeterministic: true
                )
            )
        }

        // Insight 4: Savings goal trajectory
        if let primaryGoal = savingsGoals.first {
            let remainingGoalCents = max(0, primaryGoal.targetAmountCents - primaryGoal.currentSavedCents)
            let progressPct = primaryGoal.targetAmountCents > 0
                ? Int(round(Double(primaryGoal.currentSavedCents) / Double(primaryGoal.targetAmountCents) * 100))
                : 100
            insights.append(
                FinancialInsight(
                    id: UUID(),
                    title: "\(primaryGoal.name) is at \(progressPct)% of your target",
                    summary: "\(AustralianMoneyFormatter.format(cents: primaryGoal.currentSavedCents)) saved toward \(AustralianMoneyFormatter.format(cents: primaryGoal.targetAmountCents)) (\(AustralianMoneyFormatter.format(cents: remainingGoalCents)) remaining).",
                    calculationDetail: "Planned savings rate of \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents)) per \(summary.totalDaysInPeriod)-day period.",
                    actionableRecommendation: summary.plannedSavingsForPeriodCents > 0
                        ? "At your planned rate of \(AustralianMoneyFormatter.format(cents: summary.plannedSavingsForPeriodCents))/period, you are steadily building toward your goal."
                        : "Set a per-payday savings target in Budgets to automatically reserve contributions before calculating your daily allowance.",
                    severity: .positive,
                    relatedCategory: nil,
                    supportingTransactionIds: [],
                    isDeterministic: true
                )
            )
        }

        return insights
    }

    // MARK: - 8. Statement CSV Parsing, Reconciliation Fingerprint & Formula Sanitization

    /// Generates a deterministic reconciliation fingerprint.
    /// Includes `occurrenceIndexInBatch` so two legitimate identical purchases (e.g., two $4.80 Opal taps or coffees on the same day in the same statement)
    /// are NOT falsely discarded, while re-importing the same CSV file idempotently detects both as duplicates.
    public static func makeReconciliationFingerprint(
        accountId: UUID,
        date: Date,
        amountCents: MoneyCents,
        direction: TransactionDirection,
        rawDescription: String,
        sourceTransactionId: String?,
        occurrenceIndexInBatch: Int = 0
    ) -> String {
        if let srcId = sourceTransactionId, !srcId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "SRC:\(accountId.uuidString):\(srcId.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let dayKey = formatter.string(from: date)
        let normDesc = rawDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "  ", with: " ")
        return "FP:\(accountId.uuidString):\(dayKey):\(direction.rawValue):\(amountCents):\(normDesc):#\(occurrenceIndexInBatch)"
    }

    /// Prevents CSV Formula Injection (DDE / spreadsheet command execution) when exporting user data.
    /// Any field starting with `=`, `+`, `-`, `@`, `\t`, or `\r` is prefixed with a single quote `'` and properly quoted.
    public static func sanitizeCSVCell(_ value: String) -> String {
        var safe = value
        if let first = safe.first, ["=", "+", "-", "@", "\t", "\r"].contains(first) {
            safe = "'" + safe
        }
        let escaped = safe.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.hasPrefix("'") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    /// Auto-detects column mapping from the first row of an Australian bank CSV file.
    public static func detectCSVColumnMapping(csvText: String) -> (headers: [String], mapping: CSVColumnMapping) {
        let lines = csvText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else {
            return (["Date", "Description", "Amount"], CSVColumnMapping(dateColumnIndex: 0, descriptionColumnIndex: 1, amountColumnIndex: 2, debitColumnIndex: nil, creditColumnIndex: nil, hasHeaderRow: true))
        }

        let columns = splitCSVRow(firstLine)
        let lowerCols = columns.map { $0.lowercased() }

        let hasHeader = lowerCols.contains {
            $0.contains("date") || $0.contains("description") || $0.contains("narrative") || $0.contains("amount") || $0.contains("debit")
        }

        var dateIdx = 0
        var descIdx = min(1, max(0, columns.count - 1))
        var amountIdx: Int? = columns.count > 2 ? 2 : nil
        var debitIdx: Int? = nil
        var creditIdx: Int? = nil

        if hasHeader {
            for (idx, col) in lowerCols.enumerated() {
                if col.contains("date") {
                    dateIdx = idx
                } else if col.contains("description") || col.contains("narrative") || col.contains("merchant") || col.contains("details") || col.contains("payee") {
                    descIdx = idx
                } else if col.contains("debit") || col.contains("outflow") {
                    debitIdx = idx
                } else if col.contains("credit") || col.contains("inflow") {
                    creditIdx = idx
                } else if col.contains("amount") || col.contains("value") {
                    amountIdx = idx
                }
            }
            if debitIdx != nil && creditIdx != nil {
                amountIdx = nil
            }
        }

        let headers = hasHeader ? columns : columns.enumerated().map { "Column \($0.offset + 1)" }
        return (
            headers,
            CSVColumnMapping(
                dateColumnIndex: dateIdx,
                descriptionColumnIndex: descIdx,
                amountColumnIndex: amountIdx,
                debitColumnIndex: debitIdx,
                creditColumnIndex: creditIdx,
                hasHeaderRow: hasHeader
            )
        )
    }

    /// Parses CSV text into preview rows with validation, Australian date parsing, and duplicate detection.
    public static func previewCSVStatementImport(
        csvText: String,
        mapping: CSVColumnMapping,
        accountId: UUID,
        isCreditCardAccount: Bool,
        existingTransactions: [TransactionRecord],
        userMerchantRules: [MerchantRule],
        timeZoneId: String = AustralianTimeZone.sydney.rawValue
    ) -> [ParsedCSVRowPreview] {
        let lines = csvText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let existingFingerprints = Set(existingTransactions.map(\.reconciliationFingerprint))
        var withinFileCollisionCounter: [String: Int] = [:]
        var previews: [ParsedCSVRowPreview] = []

        let startIndex = mapping.hasHeaderRow ? 1 : 0
        guard startIndex < lines.count else { return [] }

        for i in startIndex..<lines.count {
            let line = lines[i]
            let cols = splitCSVRow(line)
            let rowNumber = i + 1

            let rawDateStr = cols.indices.contains(mapping.dateColumnIndex) ? cols[mapping.dateColumnIndex] : ""
            let rawDescStr = cols.indices.contains(mapping.descriptionColumnIndex) ? cols[mapping.descriptionColumnIndex] : ""

            let parsedDate = parseAustralianBankDate(rawDateStr, timeZoneId: timeZoneId)

            var parsedCents: MoneyCents? = nil
            var direction: TransactionDirection = .debit

            if let debitCol = mapping.debitColumnIndex, let creditCol = mapping.creditColumnIndex {
                let debitStr = cols.indices.contains(debitCol) ? cols[debitCol] : ""
                let creditStr = cols.indices.contains(creditCol) ? cols[creditCol] : ""
                if let dCents = AustralianMoneyFormatter.parseToCents(debitStr), dCents != 0 {
                    parsedCents = abs(dCents)
                    direction = .debit
                } else if let cCents = AustralianMoneyFormatter.parseToCents(creditStr), cCents != 0 {
                    parsedCents = abs(cCents)
                    direction = .credit
                }
            } else if let amtCol = mapping.amountColumnIndex, cols.indices.contains(amtCol) {
                if let signedCents = AustralianMoneyFormatter.parseToCents(cols[amtCol]), signedCents != 0 {
                    parsedCents = abs(signedCents)
                    direction = signedCents < 0 ? .debit : .credit
                }
            }

            var validationError: String? = nil
            if parsedDate == nil {
                validationError = "Invalid date '\(rawDateStr)' (expected DD/MM/YYYY or YYYY-MM-DD)"
            } else if parsedCents == nil {
                validationError = "Invalid or zero monetary amount"
            } else if rawDescStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = "Missing transaction description"
            }

            let classification = classifyAustralianTransaction(
                rawDescription: rawDescStr,
                direction: direction,
                isCreditCardAccount: isCreditCardAccount,
                userMerchantRules: userMerchantRules
            )

            let effectiveDate = parsedDate ?? Date()
            let effectiveCents = parsedCents ?? 0
            let baseKey = "\(effectiveDate.timeIntervalSince1970)|\(effectiveCents)|\(direction.rawValue)|\(rawDescStr.uppercased())"
            let occurrenceIndex = withinFileCollisionCounter[baseKey, default: 0]
            withinFileCollisionCounter[baseKey] = occurrenceIndex + 1

            let fingerprint = makeReconciliationFingerprint(
                accountId: accountId,
                date: effectiveDate,
                amountCents: effectiveCents,
                direction: direction,
                rawDescription: rawDescStr,
                sourceTransactionId: nil,
                occurrenceIndexInBatch: occurrenceIndex
            )

            let isDuplicate = existingFingerprints.contains(fingerprint)

            previews.append(
                ParsedCSVRowPreview(
                    id: UUID(),
                    rowNumber: rowNumber,
                    rawLine: line,
                    parsedDate: parsedDate,
                    parsedDescription: rawDescStr,
                    parsedAmountCents: parsedCents,
                    parsedDirection: direction,
                    inferredCategory: classification.category,
                    inferredKind: classification.kind,
                    classificationConfidence: classification.confidence,
                    fingerprint: fingerprint,
                    isDuplicate: isDuplicate,
                    validationError: validationError
                )
            )
        }

        return previews
    }

    public static func parseAustralianBankDate(_ raw: String, timeZoneId: String) -> Date? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
        guard !cleaned.isEmpty else { return nil }

        let formats = [
            "dd/MM/yyyy",
            "d/M/yyyy",
            "dd-MM-yyyy",
            "yyyy-MM-dd",
            "d MMM yyyy",
            "dd MMM yyyy",
            "d MMMM yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney")
        formatter.isLenient = false

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                // Set to 12:00 PM local time to avoid midnight boundary drift across time zones
                return date.addingTimeInterval(12 * 3600)
            }
        }
        return nil
    }

    public static func splitCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }
}
