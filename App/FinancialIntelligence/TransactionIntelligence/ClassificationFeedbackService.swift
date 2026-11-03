import Foundation

// MARK: - Classification Feedback Service

/// Manages user feedback loops when a transaction's category is corrected.
/// Automatically derives clean match substrings, creates or updates workspace-isolated `MerchantRule` records,
/// applies the rule to matching unconfirmed transactions, and ensures user-confirmed transactions remain authoritative.
public final class ClassificationFeedbackService: Sendable {
    public static let shared = ClassificationFeedbackService()

    private let merchantRecognizer: MerchantRecognitionService

    public init(merchantRecognizer: MerchantRecognitionService = .shared) {
        self.merchantRecognizer = merchantRecognizer
    }

    // MARK: - Rule Derivation & Generation

    /// Automatically suggests the cleanest matching substring for a transaction so the learned rule is general enough
    /// to match future visits (e.g. "WOOLWORTHS" instead of "WOOLWORTHS 0321 SYD").
    public func deriveOptimalMatchSubstring(rawDescription: String, merchantName: String) -> String {
        let recognized = merchantRecognizer.recognize(rawDescription: rawDescription)

        // If known brand, use uppercase canonical name or first prominent token
        if recognized.isKnownMerchant {
            return recognized.canonicalName.uppercased()
        }

        // Otherwise clean description: remove terminal numbers, location suffixes, punctuation
        let words = rawDescription
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }

        if let firstWord = words.first {
            return firstWord.uppercased()
        }

        return merchantName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Creates or updates a workspace-scoped `MerchantRule` for user feedback.
    public func createOrUpdateRule(
        tenantId: String,
        matchSubstring: String,
        normalizedMerchantName: String,
        assignedCategory: AustralianCategory,
        applyToFutureOnly: Bool = false,
        existingRules: [MerchantRule]
    ) -> (rule: MerchantRule, updatedRules: [MerchantRule]) {
        let cleanSubstring = matchSubstring.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var rules = existingRules

        // Check if an existing rule with this substring already exists for this tenant
        if let existingIndex = rules.firstIndex(where: {
            $0.tenantId == tenantId &&
            $0.matchSubstring.caseInsensitiveCompare(cleanSubstring) == .orderedSame
        }) {
            var updated = rules[existingIndex]
            updated.assignedCategory = assignedCategory
            updated.normalizedMerchantName = normalizedMerchantName
            updated.applyToFutureOnly = applyToFutureOnly
            rules[existingIndex] = updated
            return (updated, rules)
        } else {
            let newRule = MerchantRule(
                id: UUID(),
                tenantId: tenantId,
                matchSubstring: cleanSubstring,
                normalizedMerchantName: normalizedMerchantName,
                assignedCategory: assignedCategory,
                applyToFutureOnly: applyToFutureOnly,
                createdAt: Date()
            )
            rules.append(newRule)
            return (newRule, rules)
        }
    }

    /// Evaluates existing unconfirmed transactions in the workspace and reapplies the learned rule
    /// without overriding transactions that were explicitly confirmed by the user.
    public func applyLearnedRuleToUnconfirmedTransactions(
        rule: MerchantRule,
        transactions: [TransactionRecord]
    ) -> (updatedTransactions: [TransactionRecord], modifiedCount: Int) {
        guard !rule.applyToFutureOnly else {
            return (transactions, 0)
        }

        let targetSubstring = rule.matchSubstring.uppercased()
        var modifiedCount = 0

        let updated = transactions.map { tx -> TransactionRecord in
            // Only update if matching tenant, not confirmed, and description matches rule
            guard tx.tenantId == rule.tenantId else { return tx }
            let descUpper = tx.rawDescription.uppercased()
            let merchantUpper = tx.merchantName.uppercased()

            let matches = descUpper.contains(targetSubstring) || merchantUpper.contains(targetSubstring)
            // If already high confidence confirmed (e.g. 1.0) and already matches, do not overwrite
            if matches && tx.category != rule.assignedCategory && tx.classificationConfidence < 0.95 {
                var copy = tx
                copy.category = rule.assignedCategory
                copy.classificationConfidence = 0.98
                copy.merchantName = rule.normalizedMerchantName.isEmpty ? tx.merchantName : rule.normalizedMerchantName
                copy.updatedAt = Date()
                modifiedCount += 1
                return copy
            }
            return tx
        }

        return (updated, modifiedCount)
    }
}
