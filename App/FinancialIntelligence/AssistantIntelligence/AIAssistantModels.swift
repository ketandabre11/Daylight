import Foundation
import SwiftUI

// MARK: - Assistant Message & Content Models

public struct AssistantMessage: Identifiable, Sendable {
    public let id: UUID
    public let isUser: Bool
    public let timestamp: Date
    public let text: String
    public let payload: AssistantPayload?

    public init(
        id: UUID = UUID(),
        isUser: Bool,
        timestamp: Date = Date(),
        text: String,
        payload: AssistantPayload? = nil
    ) {
        self.id = id
        self.isUser = isUser
        self.timestamp = timestamp
        self.text = text
        self.payload = payload
    }
}

public enum AssistantPayload: Sendable {
    case spendingSummary(SpendingSummaryData)
    case categoryBreakdown([AssistantCategorySlice])
    case savingsProgress(SavingsProgressData)
    case subscriptionsSummary(SubscriptionsData)
}

public struct SpendingSummaryData: Sendable {
    public let title: String
    public let periodLabel: String
    public let totalSpentCents: MoneyCents
    public let dailyAverageCents: MoneyCents
    public let topCategoryName: String
    public let topCategoryCents: MoneyCents

    public init(
        title: String,
        periodLabel: String,
        totalSpentCents: MoneyCents,
        dailyAverageCents: MoneyCents,
        topCategoryName: String,
        topCategoryCents: MoneyCents
    ) {
        self.title = title
        self.periodLabel = periodLabel
        self.totalSpentCents = totalSpentCents
        self.dailyAverageCents = dailyAverageCents
        self.topCategoryName = topCategoryName
        self.topCategoryCents = topCategoryCents
    }
}

public struct AssistantCategorySlice: Identifiable, Sendable {
    public var id: String { categoryName }
    public let categoryName: String
    public let icon: String
    public let amountCents: MoneyCents
    public let percentage: Double

    public init(
        categoryName: String,
        icon: String,
        amountCents: MoneyCents,
        percentage: Double
    ) {
        self.categoryName = categoryName
        self.icon = icon
        self.amountCents = amountCents
        self.percentage = percentage
    }
}

public struct SavingsProgressData: Sendable {
    public let totalSavedCents: MoneyCents
    public let activeGoalsCount: Int
    public let topGoalName: String
    public let topGoalProgress: Double

    public init(
        totalSavedCents: MoneyCents,
        activeGoalsCount: Int,
        topGoalName: String,
        topGoalProgress: Double
    ) {
        self.totalSavedCents = totalSavedCents
        self.activeGoalsCount = activeGoalsCount
        self.topGoalName = topGoalName
        self.topGoalProgress = topGoalProgress
    }
}

public struct SubscriptionsData: Sendable {
    public let totalMonthlyCents: MoneyCents
    public let count: Int
    public let items: [SubscriptionItemSnapshot]

    public init(
        totalMonthlyCents: MoneyCents,
        count: Int,
        items: [SubscriptionItemSnapshot]
    ) {
        self.totalMonthlyCents = totalMonthlyCents
        self.count = count
        self.items = items
    }
}

public struct SubscriptionItemSnapshot: Identifiable, Sendable {
    public var id: String { merchantName }
    public let merchantName: String
    public let cadence: String
    public let amountCents: MoneyCents

    public init(merchantName: String, cadence: String, amountCents: MoneyCents) {
        self.merchantName = merchantName
        self.cadence = cadence
        self.amountCents = amountCents
    }
}
