import Foundation

// MARK: - Classification Source & Structured Result

public enum ClassificationSource: String, Codable, Sendable {
    case userRule = "user_rule"
    case historicalCorrection = "historical_correction"
    case curatedMerchant = "curated_merchant"
    case systemRule = "system_rule"
    case keywordPattern = "keyword_pattern"
    case paymentRail = "payment_rail"
    case fallback = "fallback"

    public var displayName: String {
        switch self {
        case .userRule: return "User Rule"
        case .historicalCorrection: return "Past Confirmation"
        case .curatedMerchant: return "Known Merchant"
        case .systemRule: return "Banking Pattern"
        case .keywordPattern: return "Keyword Match"
        case .paymentRail: return "Payment Rail"
        case .fallback: return "Needs Review"
        }
    }
}

public struct IntelligentClassificationResult: Equatable, Sendable {
    public let normalizedMerchant: String
    public let rawDescription: String
    public let category: AustralianCategory
    public let customCategoryCode: String?
    public let kind: TransactionKind
    public let paymentRail: String?
    public let confidence: Double
    public let classificationReason: String
    public let classificationSource: ClassificationSource
    public let requiresManualReview: Bool

    public init(
        normalizedMerchant: String,
        rawDescription: String,
        category: AustralianCategory,
        customCategoryCode: String? = nil,
        kind: TransactionKind,
        paymentRail: String? = nil,
        confidence: Double,
        classificationReason: String,
        classificationSource: ClassificationSource
    ) {
        self.normalizedMerchant = normalizedMerchant
        self.rawDescription = rawDescription
        self.category = category
        self.customCategoryCode = customCategoryCode
        self.kind = kind
        self.paymentRail = paymentRail
        self.confidence = confidence
        self.classificationReason = classificationReason
        self.classificationSource = classificationSource
        self.requiresManualReview = confidence < 0.70
    }

    public var suggestedCategory: AustralianCategory { category }
    public var suggestedKind: TransactionKind { kind }
    public var reason: String { classificationReason }
    public var source: ClassificationSource { classificationSource }
    public var isManualReviewRecommended: Bool { requiresManualReview }
}

// MARK: - Intelligent Categorisation Engine

/// Evaluates merchant identity, transaction descriptions, user rules, historical user confirmations,
/// and banking rules to provide deterministic, explainable category suggestions with confidence scores.
public final class IntelligentCategorisationEngine: Sendable {
    public static let shared = IntelligentCategorisationEngine()

    private let merchantRecognizer: MerchantRecognitionService

    public init(merchantRecognizer: MerchantRecognitionService = .shared) {
        self.merchantRecognizer = merchantRecognizer
    }

    /// Evaluates all signals and returns an explainable classification.
    public func classify(
        rawDescription: String,
        amountCents: MoneyCents = 0,
        direction: TransactionDirection = .debit,
        isCreditCardAccount: Bool = false,
        userMerchantRules: [MerchantRule] = [],
        historicalTransactions: [TransactionRecord] = []
    ) -> IntelligentClassificationResult {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        // Detect Australian payment rail
        let detectedRail = detectPaymentRail(upper: upper)

        // 1. User-defined merchant rules always take highest precedence
        for rule in userMerchantRules {
            let matchTarget = rule.matchSubstring.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !matchTarget.isEmpty else { continue }

            if upper.contains(matchTarget) {
                let kind: TransactionKind = (direction == .credit) ? .income : (isCreditCardAccount ? .creditCardPurchase : .expense)
                return IntelligentClassificationResult(
                    normalizedMerchant: rule.normalizedMerchantName.isEmpty ? trimmed : rule.normalizedMerchantName,
                    rawDescription: rawDescription,
                    category: rule.assignedCategory,
                    kind: kind,
                    paymentRail: detectedRail,
                    confidence: 0.99,
                    classificationReason: "Matched your custom rule for \"\(rule.matchSubstring)\"",
                    classificationSource: .userRule
                )
            }
        }

        // 2. Internal transfers and credit card repayments (System banking rules)
        if isInternalTransfer(upper: upper) {
            return IntelligentClassificationResult(
                normalizedMerchant: "Own Account Transfer",
                rawDescription: rawDescription,
                category: .ownAccountTransfer,
                kind: .ownAccountTransfer,
                paymentRail: detectedRail ?? "Internal Transfer",
                confidence: 0.98,
                classificationReason: "Identified as an internal account transfer between your accounts",
                classificationSource: .systemRule
            )
        }

        if isCreditCardRepayment(upper: upper) {
            return IntelligentClassificationResult(
                normalizedMerchant: "Credit Card Repayment",
                rawDescription: rawDescription,
                category: .creditCardRepayment,
                kind: .creditCardRepayment,
                paymentRail: detectedRail ?? "BPAY / Internal",
                confidence: 0.98,
                classificationReason: "Identified as a credit card balance repayment",
                classificationSource: .systemRule
            )
        }

        // 3. Refunds & reversals (Must NOT be treated as ordinary income)
        if direction == .credit && isRefundOrReversal(upper: upper) {
            let isMedicare = upper.contains("MEDICARE")
            let category: AustralianCategory = isMedicare ? .healthcareMedicare : .shoppingRetail
            let kind: TransactionKind = upper.contains("REVERSAL") ? .reversal : .refund
            let merchant = isMedicare ? "Medicare Australia Rebate" : merchantRecognizer.recognize(rawDescription: rawDescription).canonicalName

            return IntelligentClassificationResult(
                normalizedMerchant: merchant,
                rawDescription: rawDescription,
                category: category,
                kind: kind,
                paymentRail: detectedRail,
                confidence: 0.95,
                classificationReason: "Credit matches a refund or rebate pattern rather than earned income",
                classificationSource: .systemRule
            )
        }

        // 4. Australian earned income and government payments
        if direction == .credit {
            if isEmploymentIncome(upper: upper) {
                return IntelligentClassificationResult(
                    normalizedMerchant: "Employer Payroll",
                    rawDescription: rawDescription,
                    category: .salaryWagesIncome,
                    kind: .income,
                    paymentRail: detectedRail ?? "Direct Credit",
                    confidence: 0.95,
                    classificationReason: "Credit matches standard Australian salary/payroll pattern",
                    classificationSource: .systemRule
                )
            }
            if isGovernmentPayment(upper: upper) {
                return IntelligentClassificationResult(
                    normalizedMerchant: "Services Australia",
                    rawDescription: rawDescription,
                    category: .governmentPayments,
                    kind: .income,
                    paymentRail: "Direct Credit",
                    confidence: 0.96,
                    classificationReason: "Identified as Services Australia / Centrelink statutory benefit",
                    classificationSource: .systemRule
                )
            }
        }

        // 5. Merchant Recognition Service lookup
        let recognized = merchantRecognizer.recognize(rawDescription: rawDescription)
        let defaultPurchaseKind: TransactionKind = isCreditCardAccount ? .creditCardPurchase : .expense

        // 6. Historical User-Confirmed Transactions (Learning from past user confirmations)
        if !historicalTransactions.isEmpty {
            let matchingConfirmed = historicalTransactions.filter { tx in
                // Only consider transactions where user previously confirmed or where confidence was >= 0.90
                tx.merchantName.caseInsensitiveCompare(recognized.canonicalName) == .orderedSame &&
                tx.category != .cashAndUnclassified &&
                tx.direction == direction
            }

            if !matchingConfirmed.isEmpty {
                // Find most frequent category user selected for this merchant
                let categoryCounts = Dictionary(grouping: matchingConfirmed, by: \.category)
                    .mapValues(\.count)
                if let (topCat, count) = categoryCounts.max(by: { $0.value < $1.value }), count >= 1 {
                    let totalMatches = matchingConfirmed.count
                    let agreementRatio = Double(count) / Double(totalMatches)
                    if agreementRatio >= 0.70 {
                        let confidence = min(0.96, 0.88 + (Double(count) * 0.02))
                        return IntelligentClassificationResult(
                            normalizedMerchant: recognized.canonicalName,
                            rawDescription: rawDescription,
                            category: topCat,
                            kind: direction == .credit ? .income : defaultPurchaseKind,
                            paymentRail: detectedRail,
                            confidence: confidence,
                            classificationReason: "Learned from \(count) previously confirmed \(recognized.canonicalName) transaction\(count == 1 ? "" : "s")",
                            classificationSource: .historicalCorrection
                        )
                    }
                }
            }
        }

        // 7. Curated Australian Merchant Directory classification
        if recognized.isKnownMerchant, let defaultCategory = recognized.defaultCategory {
            return IntelligentClassificationResult(
                normalizedMerchant: recognized.canonicalName,
                rawDescription: rawDescription,
                category: defaultCategory,
                kind: direction == .credit ? .income : defaultPurchaseKind,
                paymentRail: detectedRail,
                confidence: recognized.confidence,
                classificationReason: "Recognized Australian brand \"\(recognized.canonicalName)\"",
                classificationSource: .curatedMerchant
            )
        }

        // 8. Keyword-based pattern classification
        if let keywordMatch = matchKeywordPatterns(upper: upper, direction: direction, isCreditCard: isCreditCardAccount) {
            return IntelligentClassificationResult(
                normalizedMerchant: recognized.canonicalName,
                rawDescription: rawDescription,
                category: keywordMatch.category,
                kind: keywordMatch.kind,
                paymentRail: detectedRail,
                confidence: keywordMatch.confidence,
                classificationReason: "Matched category keyword \"\(keywordMatch.keyword)\"",
                classificationSource: .keywordPattern
            )
        }

        // 9. Fallback: low confidence (< 0.70) requiring manual review
        let fallbackCategory: AustralianCategory = direction == .credit ? .salaryWagesIncome : .cashAndUnclassified
        let fallbackKind: TransactionKind = direction == .credit ? .income : defaultPurchaseKind

        return IntelligentClassificationResult(
            normalizedMerchant: recognized.canonicalName,
            rawDescription: rawDescription,
            category: fallbackCategory,
            kind: fallbackKind,
            paymentRail: detectedRail,
            confidence: 0.40,
            classificationReason: "Ambiguous merchant description — requires your confirmation",
            classificationSource: .fallback
        )
    }

    /// Convenience overload supporting `userRules` argument name and defaulting direction to .debit
    public func classify(
        rawDescription: String,
        amountCents: MoneyCents = 0,
        direction: TransactionDirection = .debit,
        isCreditCardAccount: Bool = false,
        userRules: [MerchantRule] = [],
        historicalTransactions: [TransactionRecord] = []
    ) -> IntelligentClassificationResult {
        classify(
            rawDescription: rawDescription,
            amountCents: amountCents,
            direction: direction,
            isCreditCardAccount: isCreditCardAccount,
            userMerchantRules: userRules,
            historicalTransactions: historicalTransactions
        )
    }

    // MARK: - Private Detection Helpers

    private func detectPaymentRail(upper: String) -> String? {
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
    }

    private func isInternalTransfer(upper: String) -> Bool {
        upper.contains("INTERNAL TRANSFER") ||
        upper.contains("TRANSFER TO OFFSET") ||
        upper.contains("TRANSFER TO SAVINGS") ||
        upper.contains("TRANSFER FROM SAVINGS") ||
        upper.contains("OWN ACCOUNT") ||
        upper.contains("TFR TO") ||
        upper.contains("TFR FROM") ||
        upper.contains("INTER-ACCOUNT TRANSFER")
    }

    private func isCreditCardRepayment(upper: String) -> Bool {
        upper.contains("CREDIT CARD REPAYMENT") ||
        upper.contains("CC REPAYMENT") ||
        upper.contains("CARD AUTOPAY") ||
        upper.contains("CREDIT CARD PAYMENT")
    }

    private func isRefundOrReversal(upper: String) -> Bool {
        upper.contains("REFUND") ||
        upper.contains("REBATE") ||
        upper.contains("MEDICARE") ||
        upper.contains("REVERSAL") ||
        upper.contains("RETURN CREDIT")
    }

    private func isEmploymentIncome(upper: String) -> Bool {
        upper.contains("SALARY") ||
        upper.contains("PAYROLL") ||
        upper.contains("WAGES") ||
        upper.contains("REMUNERATION") ||
        upper.contains("PAYSLIP")
    }

    private func isGovernmentPayment(upper: String) -> Bool {
        upper.contains("SERVICES AUSTRALIA") ||
        upper.contains("CENTRELINK") ||
        upper.contains("FAMILY TAX") ||
        upper.contains("PARENTING PYMT") ||
        upper.contains("JOBSEEKER")
    }

    private struct KeywordMatch {
        let keyword: String
        let category: AustralianCategory
        let kind: TransactionKind
        let confidence: Double
    }

    private func matchKeywordPatterns(upper: String, direction: TransactionDirection, isCreditCard: Bool) -> KeywordMatch? {
        let purchaseKind: TransactionKind = isCreditCard ? .creditCardPurchase : .expense

        let patterns: [(keyword: String, category: AustralianCategory, kind: TransactionKind, confidence: Double)] = [
            ("COFFEE", .cafesAndTakeaway, purchaseKind, 0.86),
            ("CAFE", .cafesAndTakeaway, purchaseKind, 0.86),
            ("BAKERY", .cafesAndTakeaway, purchaseKind, 0.85),
            ("ESPRESSO", .cafesAndTakeaway, purchaseKind, 0.85),
            ("RESTAURANT", .restaurantsAndDelivery, purchaseKind, 0.87),
            ("PIZZERIA", .restaurantsAndDelivery, purchaseKind, 0.86),
            ("SUSHI", .restaurantsAndDelivery, purchaseKind, 0.85),
            ("PHARMACY", .healthcareMedicare, purchaseKind, 0.88),
            ("CHEMIST", .healthcareMedicare, purchaseKind, 0.88),
            ("DENTAL", .healthcareMedicare, purchaseKind, 0.89),
            ("MEDICAL", .healthcareMedicare, purchaseKind, 0.88),
            ("CLINIC", .healthcareMedicare, purchaseKind, 0.86),
            ("PHYSIO", .healthcareMedicare, purchaseKind, 0.87),
            ("OPTOMETRY", .healthcareMedicare, purchaseKind, 0.87),
            ("TAXI", .fuelTollsVehicle, purchaseKind, 0.85),
            ("CAB", .fuelTollsVehicle, purchaseKind, 0.80),
            ("PARKING", .fuelTollsVehicle, purchaseKind, 0.87),
            ("SERVICE STATION", .fuelTollsVehicle, purchaseKind, 0.88),
            ("PETROL", .fuelTollsVehicle, purchaseKind, 0.88),
            ("FITNESS", .gymFitness, purchaseKind, 0.86),
            ("PILATES", .gymFitness, purchaseKind, 0.86),
            ("YOGA", .gymFitness, purchaseKind, 0.85),
            ("STRATA", .councilRatesStrata, purchaseKind, 0.90),
            ("RATES", .councilRatesStrata, purchaseKind, 0.88),
            ("INSURANCE", .insurance, purchaseKind, 0.89),
            ("ATM WITHDRAWAL", .cashAndUnclassified, .cashWithdrawal, 0.92),
            ("CASH WITHDRAWAL", .cashAndUnclassified, .cashWithdrawal, 0.92)
        ]

        for p in patterns {
            if upper.contains(p.keyword) {
                return KeywordMatch(keyword: p.keyword, category: p.category, kind: p.kind, confidence: p.confidence)
            }
        }
        return nil
    }
}
