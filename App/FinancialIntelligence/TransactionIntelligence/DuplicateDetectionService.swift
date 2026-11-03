import Foundation

// MARK: - Duplicate Models

public enum DuplicateStatus: String, Codable, Sendable {
    /// Exact match on bank source transaction ID or reconciliation fingerprint.
    case confirmedDuplicate = "confirmed_duplicate"
    /// Multi-factor heuristic match: identical amount, direction, merchant, and timestamps within 48 hours.
    case potentialDuplicate = "potential_duplicate"

    public var displayName: String {
        switch self {
        case .confirmedDuplicate: return "Confirmed Duplicate"
        case .potentialDuplicate: return "Potential Duplicate"
        }
    }
}

public struct DuplicateCandidateGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let tenantId: String
    public let primaryTransaction: TransactionRecord
    public let duplicateTransaction: TransactionRecord
    public let confidence: Double
    public let status: DuplicateStatus
    public let matchingEvidence: [String]
    public let timeDifferenceHours: Double

    public init(
        id: String,
        tenantId: String,
        primaryTransaction: TransactionRecord,
        duplicateTransaction: TransactionRecord,
        confidence: Double,
        status: DuplicateStatus,
        matchingEvidence: [String],
        timeDifferenceHours: Double
    ) {
        self.id = id
        self.tenantId = tenantId
        self.primaryTransaction = primaryTransaction
        self.duplicateTransaction = duplicateTransaction
        self.confidence = confidence
        self.status = status
        self.matchingEvidence = matchingEvidence
        self.timeDifferenceHours = timeDifferenceHours
    }
}

// MARK: - Duplicate Detection Service

/// Detects confirmed and potential duplicate transactions across an account or workspace without ever
/// deleting or altering records automatically. Supports user dismissal to prevent repeated alerts.
public final class DuplicateDetectionService: Sendable {
    public static let shared = DuplicateDetectionService()

    public init() {}

    /// Detects duplicate candidates among transactions, excluding any dismissed group IDs.
    public func detectDuplicates(
        transactions: [TransactionRecord],
        dismissedPairIds: Set<String> = []
    ) -> [DuplicateCandidateGroup] {
        guard transactions.count >= 2 else { return [] }

        var results: [DuplicateCandidateGroup] = []
        let sorted = transactions.sorted { $0.occurredAt < $1.occurredAt }

        // Compare each pair within a 48-hour rolling window
        let maxTimeWindowSeconds: TimeInterval = 48 * 3600

        for i in 0..<sorted.count {
            let tx1 = sorted[i]
            // Skip transfers and credit card repayments as these naturally balance on both sides
            if tx1.kind == .ownAccountTransfer || tx1.kind == .creditCardRepayment || tx1.status == .reversed {
                continue
            }

            for j in (i + 1)..<sorted.count {
                let tx2 = sorted[j]
                let timeDiff = tx2.occurredAt.timeIntervalSince(tx1.occurredAt)

                // Since sorted by date, break early if past the time window
                if timeDiff > maxTimeWindowSeconds {
                    break
                }

                // Check tenant isolation (must belong to same tenant)
                guard tx1.tenantId == tx2.tenantId else { continue }

                // Deterministic pair ID independent of comparison order
                let pairId = makePairId(tx1.id, tx2.id)
                guard !dismissedPairIds.contains(pairId) else { continue }

                // 1. Confirmed duplicate: Identical reconciliation fingerprint or identical source transaction ID
                if !tx1.reconciliationFingerprint.isEmpty && tx1.reconciliationFingerprint == tx2.reconciliationFingerprint {
                    results.append(
                        DuplicateCandidateGroup(
                            id: pairId,
                            tenantId: tx1.tenantId,
                            primaryTransaction: tx1,
                            duplicateTransaction: tx2,
                            confidence: 1.0,
                            status: .confirmedDuplicate,
                            matchingEvidence: [
                                "Exact matching bank reconciliation fingerprint (\(tx1.reconciliationFingerprint.prefix(8))...)",
                                "Identical amount of \(AustralianMoneyFormatter.format(cents: tx1.amountCents))",
                                "Occurred within \(formatHours(timeDiff))"
                            ],
                            timeDifferenceHours: timeDiff / 3600.0
                        )
                    )
                    continue
                }

                if let src1 = tx1.sourceTransactionId, let src2 = tx2.sourceTransactionId,
                   !src1.isEmpty && src1 == src2 && tx1.accountId == tx2.accountId {
                    results.append(
                        DuplicateCandidateGroup(
                            id: pairId,
                            tenantId: tx1.tenantId,
                            primaryTransaction: tx1,
                            duplicateTransaction: tx2,
                            confidence: 1.0,
                            status: .confirmedDuplicate,
                            matchingEvidence: [
                                "Matching bank reference identifier: \(src1)",
                                "Identical account and amount of \(AustralianMoneyFormatter.format(cents: tx1.amountCents))"
                            ],
                            timeDifferenceHours: timeDiff / 3600.0
                        )
                    )
                    continue
                }

                // 2. Potential duplicate: Multi-factor heuristic
                // Must have exact same account, amount, and direction
                guard tx1.accountId == tx2.accountId,
                      tx1.amountCents == tx2.amountCents,
                      tx1.direction == tx2.direction else {
                    continue
                }

                var evidence: [String] = []
                var score = 0.50

                evidence.append("Identical amount: \(AustralianMoneyFormatter.format(cents: tx1.amountCents)) (\(tx1.direction.rawValue))")
                score += 0.20
                evidence.append("Charged to the same account")

                // Compare merchant names - potential duplicates must have merchant or description similarity
                let m1 = tx1.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let m2 = tx2.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let desc1 = tx1.rawDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let desc2 = tx2.rawDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                let hasExactMerchant = (m1 == m2 && !m1.isEmpty)
                let hasExactDesc = (desc1 == desc2 && !desc1.isEmpty)
                let hasSimilarMerchant = (!m1.isEmpty && !m2.isEmpty && (m1.contains(m2) || m2.contains(m1)))

                guard hasExactMerchant || hasExactDesc || hasSimilarMerchant else {
                    continue
                }

                if hasExactMerchant {
                    score += 0.20
                    evidence.append("Exact merchant match: \"\(tx1.merchantName)\"")
                } else if hasExactDesc {
                    score += 0.20
                    evidence.append("Exact bank description match")
                } else if hasSimilarMerchant {
                    score += 0.15
                    evidence.append("Similar merchant names (\"\(tx1.merchantName)\" vs \"\(tx2.merchantName)\")")
                }

                // Tight time proximity adds confidence
                if timeDiff < 300 { // within 5 minutes
                    score += 0.10
                    evidence.append("Occurred within 5 minutes of each other (possible double-swipe)")
                } else if timeDiff < 3600 { // within 1 hour
                    score += 0.05
                    evidence.append("Occurred within 1 hour (\(formatHours(timeDiff)))")
                } else {
                    evidence.append("Occurred \(formatHours(timeDiff)) apart")
                }

                if score >= 0.75 {
                    results.append(
                        DuplicateCandidateGroup(
                            id: pairId,
                            tenantId: tx1.tenantId,
                            primaryTransaction: tx1,
                            duplicateTransaction: tx2,
                            confidence: min(0.95, score),
                            status: .potentialDuplicate,
                            matchingEvidence: evidence,
                            timeDifferenceHours: timeDiff / 3600.0
                        )
                    )
                }
            }
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    public func makePairId(_ id1: UUID, _ id2: UUID) -> String {
        let sortedIds = [id1.uuidString, id2.uuidString].sorted()
        return "dup_\(sortedIds[0])_\(sortedIds[1])"
    }

    private func formatHours(_ seconds: TimeInterval) -> String {
        let hours = Int(round(seconds / 3600.0))
        if hours < 1 {
            let minutes = max(1, Int(round(seconds / 60.0)))
            return "\(minutes) min"
        }
        return "\(hours) hr\(hours == 1 ? "" : "s")"
    }
}
