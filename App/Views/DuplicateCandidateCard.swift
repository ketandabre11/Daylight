import SwiftUI

public struct DuplicateCandidateCard: View {
    let group: DuplicateCandidateGroup
    let store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme
    let onInspect: () -> Void

    public init(
        group: DuplicateCandidateGroup,
        store: DaylightStore,
        onInspect: @escaping () -> Void
    ) {
        self.group = group
        self.store = store
        self.onInspect = onInspect
    }

    private var isConfirmed: Bool {
        group.status == .confirmedDuplicate
    }

    private var headerView: some View {
        HStack {
            DaylightBadge(
                group.status.displayName,
                icon: isConfirmed ? "exclamationmark.octagon.fill" : "doc.on.doc",
                tone: isConfirmed ? .overBudget : .warning
            )
            Spacer()
            Button("Dismiss") {
                store.dismissDuplicateCandidate(id: group.id)
            }
            .font(DaylightTypography.caption)
            .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
        }
    }

    private var primaryRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Original: \(group.primaryTransaction.merchantName)")
                    .font(DaylightTypography.bodyMedium)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                Text(AustralianDateHelper.formatDateTime(group.primaryTransaction.occurredAt, timeZoneId: store.profile.timeZoneId))
                    .font(DaylightTypography.caption)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
            }
            Spacer()
            Text(AustralianMoneyFormatter.format(cents: group.primaryTransaction.amountCents))
                .font(DaylightTypography.financialAmount(size: 14, weight: .bold))
        }
    }

    private var candidateRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Candidate: \(group.duplicateTransaction.merchantName)")
                    .font(DaylightTypography.bodyMedium)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                Text(AustralianDateHelper.formatDateTime(group.duplicateTransaction.occurredAt, timeZoneId: store.profile.timeZoneId))
                    .font(DaylightTypography.caption)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
            }
            Spacer()
            Button("Inspect") {
                onInspect()
            }
            .font(DaylightTypography.caption)
        }
    }

    private var evidenceText: String {
        group.matchingEvidence.map { "• \($0)" }.joined(separator: "\n")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            primaryRow
            candidateRow

            if !group.matchingEvidence.isEmpty {
                Text(evidenceText)
                    .font(DaylightTypography.caption)
                    .foregroundStyle(DaylightTheme.textSecondary(for: colorScheme))
            }
        }
        .padding(DaylightTheme.Spacing.sm)
        .background(DaylightTheme.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: DaylightTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.md)
                .stroke(DaylightTheme.warning.opacity(0.3), lineWidth: 1)
        )
    }
}
