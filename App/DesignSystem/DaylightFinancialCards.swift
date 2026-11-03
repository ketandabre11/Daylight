import SwiftUI

// MARK: - Reusable Premium Glass Balance Card

/// A hero financial glass card displaying Safe-to-Spend, everyday available balance,
/// today's spending, and next pay date with an optional privacy toggle.
public struct DaylightBalanceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    public let safeToSpendCents: MoneyCents
    public let availableBalanceCents: MoneyCents
    public let spentTodayCents: MoneyCents
    public let nextPayDate: Date
    public let daysUntilNextPay: Int
    public let isOverDailyAllowance: Bool
    public let ringProgress: Double
    public let timeZoneId: String
    @Binding public var isAmountsHidden: Bool
    public let onInfoTapped: () -> Void

    public init(
        safeToSpendCents: MoneyCents,
        availableBalanceCents: MoneyCents,
        spentTodayCents: MoneyCents,
        nextPayDate: Date,
        daysUntilNextPay: Int,
        isOverDailyAllowance: Bool,
        ringProgress: Double,
        timeZoneId: String,
        isAmountsHidden: Binding<Bool>,
        onInfoTapped: @escaping () -> Void
    ) {
        self.safeToSpendCents = safeToSpendCents
        self.availableBalanceCents = availableBalanceCents
        self.spentTodayCents = spentTodayCents
        self.nextPayDate = nextPayDate
        self.daysUntilNextPay = daysUntilNextPay
        self.isOverDailyAllowance = isOverDailyAllowance
        self.ringProgress = ringProgress
        self.timeZoneId = timeZoneId
        self._isAmountsHidden = isAmountsHidden
        self.onInfoTapped = onInfoTapped
    }

    private var formattedSafeToSpend: String {
        if isAmountsHidden { return "••••••" }
        return AustralianMoneyFormatter.format(cents: safeToSpendCents)
    }

    private var formattedAvailable: String {
        if isAmountsHidden { return "••••••" }
        return AustralianMoneyFormatter.format(cents: availableBalanceCents)
    }

    private var formattedSpentToday: String {
        if isAmountsHidden { return "••••••" }
        return AustralianMoneyFormatter.format(cents: spentTodayCents)
    }

    private var activeHighlightColor: Color {
        isOverDailyAllowance
            ? DaylightTheme.warning
            : (colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald)
    }

    public var body: some View {
        DaylightGlassCard(padding: DaylightTheme.Spacing.cardPadding, isElevated: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Top Meta Row
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(activeHighlightColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: activeHighlightColor.opacity(0.4), radius: 4)

                        Text("Safe-to-Spend Today")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAmountsHidden.toggle()
                            }
                        } label: {
                            Image(systemName: isAmountsHidden ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DaylightTheme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? DaylightTheme.Glass.translucent : DaylightTheme.lightCreamElevated)
                                        .overlay(Circle().stroke(DaylightTheme.glassBorder, lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAmountsHidden ? "Show financial amounts" : "Hide financial amounts")

                        Button(action: onInfoTapped) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(activeHighlightColor)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? DaylightTheme.Glass.translucent : DaylightTheme.lightCreamElevated)
                                        .overlay(Circle().stroke(DaylightTheme.glassBorder, lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How Safe-to-Spend is calculated")
                    }
                }

                // Hero Amount + Visual Gauge
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedSafeToSpend)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(activeHighlightColor)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .shadow(
                                color: activeHighlightColor.opacity(colorScheme == .dark ? 0.35 : 0.08),
                                radius: colorScheme == .dark ? 12 : 2,
                                x: 0,
                                y: colorScheme == .dark ? 4 : 1
                            )

                        Text(isOverDailyAllowance ? "Over daily allowance (re-balanced tomorrow)" : "Available to spend comfortably today")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Compact Circular Progress Ring
                    ZStack {
                        Circle()
                            .stroke(DaylightTheme.glassBorder, lineWidth: 5)
                            .frame(width: 52, height: 52)

                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(ringProgress, 0.0), 1.0)))
                            .stroke(
                                activeHighlightColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 52, height: 52)

                        Text("\(Int(min(max(ringProgress, 0.0), 1.0) * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DaylightTheme.textPrimary)
                    }
                }

                // Divider Line
                Rectangle()
                    .fill(DaylightTheme.dividerColor)
                    .frame(height: 1)

                // Secondary Metrics Grid
                HStack(alignment: .top, spacing: 0) {
                    balanceSubMetric(
                        label: "Available",
                        value: formattedAvailable,
                        icon: "building.columns.fill"
                    )

                    Spacer()

                    balanceSubMetric(
                        label: "Spent Today",
                        value: formattedSpentToday,
                        icon: "arrow.up.right"
                    )

                    Spacer()

                    balanceSubMetric(
                        label: "Next Pay",
                        value: AustralianDateHelper.formatShortDate(nextPayDate, timeZoneId: timeZoneId),
                        icon: "calendar"
                    )
                }
            }
        }
    }

    private func balanceSubMetric(
        label: String,
        value: String,
        icon: String,
        subtext: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activeHighlightColor)
                Text(label)
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.textSecondary)
            }
            Text(value)
                .font(DaylightTypography.financialAmount(size: 14, weight: .semibold))
                .foregroundStyle(DaylightTheme.textPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            if let subtext {
                Text(subtext)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DaylightTheme.textMuted)
            }
        }
    }
}

// MARK: - Reusable Premium Glass Transaction Row

/// A glass transaction row displaying merchant identity, category icon, date, and amount.
public struct DaylightTransactionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    public let transaction: TransactionRecord
    public let timeZoneId: String
    public let isAmountsHidden: Bool
    public let onTap: () -> Void

    public init(
        transaction: TransactionRecord,
        timeZoneId: String,
        isAmountsHidden: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.transaction = transaction
        self.timeZoneId = timeZoneId
        self.isAmountsHidden = isAmountsHidden
        self.onTap = onTap
    }

    private var formattedAmount: String {
        if isAmountsHidden { return "••••" }
        return AustralianMoneyFormatter.format(
            cents: transaction.direction == .debit ? -transaction.amountCents : transaction.amountCents,
            showPlusForPositive: true
        )
    }

    private var amountColor: Color {
        if transaction.direction == .credit {
            return colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
        }
        return DaylightTheme.textPrimary
    }

    private var categoryBadgeColor: Color {
        if transaction.direction == .credit {
            return colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
        }
        return colorScheme == .dark ? DaylightTheme.Lime.mint : DaylightTheme.accentEmerald
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Category / Merchant Icon Badge
                ZStack {
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? DaylightTheme.Glass.translucent
                                : Color(red: 236/255, green: 245/255, blue: 240/255)
                        )
                        .background(Circle().fill(.ultraThinMaterial.opacity(0.5)))
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(DaylightTheme.glassBorder, lineWidth: 1))

                    Image(systemName: transaction.category.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(categoryBadgeColor)
                }

                // Merchant Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(transaction.merchantName)
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.textPrimary)
                            .lineLimit(1)

                        if transaction.status == .pending {
                            Text("Pending")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DaylightTheme.Emerald.forest)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DaylightTheme.warning))
                        }

                        if transaction.classificationConfidence < 0.70 {
                            Text("Review")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DaylightTheme.Emerald.forest)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DaylightTheme.Lime.primary))
                        }
                    }

                    Text("\(transaction.category.displayName) • \(AustralianDateHelper.formatShortDate(transaction.occurredAt, timeZoneId: timeZoneId))")
                        .font(DaylightTypography.finePrint)
                        .foregroundStyle(DaylightTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedAmount)
                        .font(DaylightTypography.financialAmount(size: 15, weight: .bold))
                        .foregroundStyle(amountColor)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    Text(kindLabel(for: transaction))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DaylightTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : DaylightTheme.lightCream)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.35 : 0.80))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DaylightTheme.glassBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func kindLabel(for tx: TransactionRecord) -> String {
        switch tx.kind {
        case .income:
            return "Income"
        case .refund, .reversal:
            return "Refund"
        case .ownAccountTransfer, .creditCardRepayment:
            return "Transfer"
        default:
            return tx.excludeFromBudget ? "Excluded" : "Expense"
        }
    }
}

// MARK: - Reusable Premium Glass Insight Card

/// A glass card presenting verified financial intelligence and recommendations.
public struct DaylightInsightCard: View {
    @Environment(\.colorScheme) private var colorScheme
    public let insight: FinancialInsight
    public let onAction: () -> Void

    public init(insight: FinancialInsight, onAction: @escaping () -> Void) {
        self.insight = insight
        self.onAction = onAction
    }

    private var accentColor: Color {
        colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
    }

    public var body: some View {
        DaylightGlassCard(padding: DaylightTheme.Spacing.cardPadding, isElevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DaylightTheme.Emerald.forest)
                        Text("Financial Intelligence")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DaylightTheme.Emerald.forest)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DaylightTheme.Lime.primary))

                    Spacer()

                    Button("View All", action: onAction)
                        .font(DaylightTypography.captionMedium)
                        .foregroundStyle(accentColor)
                }

                Text(insight.title)
                    .font(DaylightTypography.sectionTitle)
                    .foregroundStyle(DaylightTheme.textPrimary)

                Text(insight.summary)
                    .font(DaylightTypography.callout)
                    .foregroundStyle(DaylightTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.actionableRecommendation.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .padding(.top, 2)

                        Text(insight.actionableRecommendation)
                            .font(DaylightTypography.caption)
                            .foregroundStyle(colorScheme == .dark ? DaylightTheme.Lime.mint : DaylightTheme.Emerald.forest)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? DaylightTheme.Emerald.secondary.opacity(0.35)
                                    : Color(red: 238/255, green: 247/255, blue: 241/255)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? DaylightTheme.Lime.primary.opacity(0.20)
                                    : DaylightTheme.accentEmerald.opacity(0.20),
                                lineWidth: 1
                            )
                    )
                }
            }
        }
    }
}
