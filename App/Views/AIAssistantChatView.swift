import SwiftUI

public struct AIAssistantChatView: View {
    private enum ChatLayout {
        static let controlSize: CGFloat = 44
        static let outerMargin: CGFloat = 8
        static let contentPadding: CGFloat = 10
        static let controlSpacing: CGFloat = 10
        static let verticalPadding: CGFloat = 8
    }

    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText: String = ""
    @State private var messages: [AssistantMessage] = []
    @State private var showingVoiceSheet: Bool = false
    @FocusState private var isInputFocused: Bool

    public init(store: DaylightStore) {
        self.store = store
    }

    private let suggestedPrompts = [
        "Where did my money go this month?",
        "Why did my spending increase?",
        "How much did I save this month?",
        "What are my biggest expenses?",
        "How much do I spend on subscriptions?"
    ]

    private var accentColor: Color {
        colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Fixed Glass Header
            chatHeader

            // 2. Scrollable Message Feed
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: DaylightTheme.Spacing.md) {
                        if messages.isEmpty {
                            assistantWelcomeCard
                        }

                        ForEach(messages) { msg in
                            if msg.isUser {
                                userMessageBubble(msg)
                            } else {
                                assistantMessageBubble(msg)
                            }
                        }

                        if messages.isEmpty || !(messages.last?.isUser ?? false) {
                            suggestedPromptsSection
                                .padding(.top, DaylightTheme.Spacing.xs)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom_anchor")
                    }
                    .padding(.horizontal, DaylightTheme.Spacing.screenMargin)
                    .padding(.vertical, DaylightTheme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom_anchor", anchor: .bottom)
                    }
                }
            }

            // 3. Pinned Message Composer (Above Home Indicator / Keyboard)
            messageComposer
                .padding(.bottom, 6)
        }
        .background(DaylightAtmosphericBackground())
        .onAppear {
            if messages.isEmpty {
                seedInitialGreeting()
                if ProcessInfo.processInfo.arguments.contains("-testChatOverflow") {
                    seedTestConversation()
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-voice") {
                showingVoiceSheet = true
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingVoiceSheet) {
            AIVoiceAssistantView(store: store)
        }
    }

    // MARK: - 1. Fixed Glass Header

    private var chatHeader: some View {
        HStack(alignment: .center, spacing: ChatLayout.controlSpacing) {
            DaylightGlassIconButton(icon: "chevron.left") {
                dismiss()
                store.selectedSection = .overview
            }
            .accessibilityLabel("Back to Overview")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DaylightAI")
                        .font(DaylightTypography.subheadlineMedium)
                        .foregroundStyle(DaylightTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Circle()
                        .fill(DaylightTheme.Lime.primary)
                        .frame(width: 7, height: 7)
                }

                Text("Your own Assistant")
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()

            DaylightGlassIconButton(icon: "arrow.counterclockwise") {
                resetConversation()
            }
            .accessibilityLabel("Reset conversation")
        }
        .padding(.horizontal, ChatLayout.contentPadding)
        .frame(minHeight: ChatLayout.controlSize)
        .padding(.vertical, ChatLayout.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                .fill(colorScheme == .dark ? DaylightTheme.Glass.translucent : Color.white.opacity(0.92))
                .background(.ultraThinMaterial.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                        .stroke(DaylightTheme.glassBorder, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous))
        .padding(.horizontal, ChatLayout.outerMargin)
        .padding(.top, ChatLayout.outerMargin)
    }

    // MARK: - Welcome Card

    private var assistantWelcomeCard: some View {
        DaylightGlassCard(padding: DaylightTheme.Spacing.cardPadding, isElevated: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)

                    Text("PRIVATE & SECURE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .tracking(0.8)
                }

                Text("Hi \(store.greetingName)! I analyze your actual Daylight records to answer questions about your spending, Safe-to-Spend limits, upcoming bills, and savings.")
                    .font(DaylightTypography.callout)
                    .foregroundStyle(DaylightTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(colorScheme == .dark ? DaylightTheme.Lime.mint : DaylightTheme.accentEmerald)
                    Text("100% on-device processing. No financial transactions leave your phone.")
                        .font(DaylightTypography.finePrint)
                        .foregroundStyle(DaylightTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - 2. Message Bubbles

    private func sanitizeForWrapping(_ text: String) -> String {
        var result = ""
        for char in text {
            result.append(char)
            if ["/", "?", "&", "=", "_", "-", "."].contains(char) {
                result.append("\u{200B}")
            }
        }
        return result
    }

    private func userMessageBubble(_ msg: AssistantMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 50)

            Text(sanitizeForWrapping(msg.text))
                .font(DaylightTypography.callout)
                .foregroundStyle(DaylightTheme.Emerald.forest) // Always dark forest green on lime (13.8:1 contrast)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, ChatLayout.contentPadding)
                .frame(height: ChatLayout.controlSize)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DaylightTheme.Lime.primary)
                )
                .shadow(
                    color: DaylightTheme.Lime.glow.opacity(colorScheme == .dark ? 0.35 : 0.15),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func assistantMessageBubble(_ msg: AssistantMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Assistant Avatar
            ZStack {
                Circle()
                    .fill(DaylightTheme.Lime.primary)
                    .frame(width: 32, height: 32)
                    .shadow(color: DaylightTheme.Lime.glow.opacity(0.3), radius: 4)

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DaylightTheme.Emerald.forest)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                // Main Bubble
                Text(sanitizeForWrapping(msg.text))
                    .font(DaylightTypography.callout)
                    .foregroundStyle(DaylightTheme.textPrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.6 : 0.9))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DaylightTheme.glassBorder, lineWidth: 1)
                    )

                // Structured Financial Response Card if present
                if let payload = msg.payload {
                    structuredPayloadView(payload)
                }
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Structured Payload Views

    @ViewBuilder
    private func structuredPayloadView(_ payload: AssistantPayload) -> some View {
        switch payload {
        case .spendingSummary(let data):
            DaylightGlassCard(padding: 12, isElevated: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(data.title)
                        .font(DaylightTypography.subheadlineMedium)
                        .foregroundStyle(DaylightTheme.textPrimary)
                        .lineLimit(2)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) {
                            spendingSummaryMetric(title: "Total Spent", amountCents: data.totalSpentCents, highlight: true)
                            spendingSummaryMetric(title: "Daily Average", amountCents: data.dailyAverageCents, highlight: false)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            spendingSummaryMetric(title: "Total Spent", amountCents: data.totalSpentCents, highlight: true)
                            spendingSummaryMetric(title: "Daily Average", amountCents: data.dailyAverageCents, highlight: false)
                        }
                    }

                    Rectangle()
                        .fill(DaylightTheme.dividerColor)
                        .frame(height: 1)

                    HStack {
                        Text("Top: \(data.topCategoryName)")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(AustralianMoneyFormatter.format(cents: data.topCategoryCents))
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(DaylightTheme.textPrimary)
                            .monospacedDigit()
                    }
                }
            }

        case .categoryBreakdown(let slices):
            DaylightGlassCard(padding: 12, isElevated: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Spending Categories")
                        .font(DaylightTypography.subheadlineMedium)
                        .foregroundStyle(DaylightTheme.textPrimary)

                    ForEach(slices.prefix(4)) { cat in
                        VStack(spacing: 4) {
                            HStack {
                                Text(cat.categoryName)
                                    .font(DaylightTypography.caption)
                                    .foregroundStyle(DaylightTheme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(AustralianMoneyFormatter.format(cents: cat.amountCents))
                                    .font(DaylightTypography.captionMedium)
                                    .foregroundStyle(DaylightTheme.textPrimary)
                                    .monospacedDigit()
                            }
                            GeometryReader { barGeo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color(red: 232/255, green: 243/255, blue: 236/255))
                                    Capsule()
                                        .fill(DaylightTheme.Lime.primary)
                                        .frame(width: max(4, barGeo.size.width * CGFloat(cat.percentage / 100.0)))
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

        case .savingsProgress(let data):
            DaylightGlassCard(padding: 12, isElevated: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(data.topGoalName)
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        DaylightBadge("\(Int(data.topGoalProgress))%", icon: "target", tone: data.topGoalProgress >= 100 ? .positive : .neutral)
                    }

                    HStack(spacing: 4) {
                        Text(AustralianMoneyFormatter.format(cents: data.totalSavedCents))
                            .font(DaylightTypography.financialAmount(size: 18, weight: .bold))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                        Text("saved across \(data.activeGoalsCount) goals")
                            .font(DaylightTypography.caption)
                            .foregroundStyle(DaylightTheme.textSecondary)
                    }
                }
            }

        case .subscriptionsSummary(let data):
            DaylightGlassCard(padding: 12, isElevated: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recurring Subscriptions")
                            .font(DaylightTypography.subheadlineMedium)
                            .foregroundStyle(DaylightTheme.textPrimary)
                        Spacer()
                        Text(AustralianMoneyFormatter.format(cents: data.totalMonthlyCents) + "/mo")
                            .font(DaylightTypography.captionMedium)
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                    }

                    Divider()

                    ForEach(data.items.prefix(5)) { item in
                        HStack {
                            Text(item.merchantName)
                                .font(DaylightTypography.caption)
                                .foregroundStyle(DaylightTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("(\(item.cadence))")
                                .font(DaylightTypography.finePrint)
                                .foregroundStyle(DaylightTheme.textMuted)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(AustralianMoneyFormatter.format(cents: item.amountCents))
                                .font(DaylightTypography.captionMedium)
                                .foregroundStyle(DaylightTheme.textSecondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func spendingSummaryMetric(title: String, amountCents: MoneyCents, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DaylightTypography.finePrint)
                .foregroundStyle(DaylightTheme.textMuted)
            Text(AustralianMoneyFormatter.format(cents: amountCents))
                .font(DaylightTypography.financialAmount(size: highlight ? 18 : 16, weight: highlight ? .bold : .semibold))
                .foregroundStyle(highlight ? accentColor : DaylightTheme.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Suggested Prompts Section

    private var suggestedPromptsSection: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xs) {
            Text("SUGGESTED QUESTIONS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(DaylightTheme.textMuted)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DaylightTheme.Spacing.xs) {
                    ForEach(suggestedPrompts, id: \.self) { prompt in
                        Button {
                            sendMessage(prompt)
                        } label: {
                            Text(prompt)
                                .font(DaylightTypography.captionMedium)
                                .foregroundStyle(DaylightTheme.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                                        .background(Capsule().fill(.ultraThinMaterial.opacity(0.65)))
                                )
                                .overlay(Capsule().stroke(DaylightTheme.glassBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - 3. Pinned Message Composer

    private var messageComposer: some View {
        HStack(spacing: 10) {
            // Text Input Field
            HStack(spacing: 8) {
                TextField("Ask about spending, budgets, savings...", text: $inputText)
                    .font(DaylightTypography.callout)
                    .foregroundStyle(DaylightTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage(inputText)
                        }
                    }

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DaylightTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.65))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                    .stroke(DaylightTheme.glassBorder, lineWidth: 1)
            )

            // Voice mic trigger (Dedicated composer mic action)
            DaylightGlassIconButton(icon: "mic.fill") {
                showingVoiceSheet = true
            }
            .accessibilityLabel("Voice assistant")

            // Send Button
            Button {
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sendMessage(inputText)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DaylightTheme.Emerald.forest)
                    .frame(width: ChatLayout.controlSize, height: ChatLayout.controlSize)
                    .background(Circle().fill(DaylightTheme.Lime.primary))
                    .shadow(color: DaylightTheme.Lime.glow.opacity(0.4), radius: 6)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1.0)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, ChatLayout.contentPadding)
        .padding(.vertical, ChatLayout.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                .fill(colorScheme == .dark ? DaylightTheme.Glass.translucent : Color.white.opacity(0.92))
                .background(.ultraThinMaterial.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous)
                        .stroke(DaylightTheme.glassBorder, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DaylightTheme.Radius.pill, style: .continuous))
        .padding(.horizontal, ChatLayout.outerMargin)
    }

    private func resetConversation() {
        withAnimation {
            messages.removeAll()
            seedInitialGreeting()
        }
    }

    private func seedInitialGreeting() {
        let greeting = AssistantMessage(
            isUser: false,
            text: "G'day! I'm your Daylight financial assistant. How can I assist you with your money today?"
        )
        messages.append(greeting)
    }

    private func seedTestConversation() {
        messages.append(AssistantMessage(
            isUser: true,
            text: "Can you provide a detailed breakdown of my flexible spending, upcoming bills, and progress toward my savings goals for this pay cycle?"
        ))
        messages.append(AssistantMessage(
            isUser: false,
            text: "Here is your spending analysis for this cycle. You have plenty of room in your Safe-to-Spend allowance.",
            payload: .spendingSummary(SpendingSummaryData(
                title: "Pay Cycle Spending Analysis",
                periodLabel: "This Cycle",
                totalSpentCents: 142050,
                dailyAverageCents: 4735,
                topCategoryName: "Groceries & Essentials",
                topCategoryCents: 62000
            ))
        ))
        messages.append(AssistantMessage(
            isUser: true,
            text: "What about https://daylight.money/help/faqs/spending-limits-and-categories? 💰🚀🇦🇺"
        ))
        messages.append(AssistantMessage(
            isUser: false,
            text: "All transactions and category analyses are computed entirely on-device with zero server transmission."
        ))
    }

    private func sendMessage(_ text: String) {
        let userMsg = AssistantMessage(isUser: true, text: text)
        messages.append(userMsg)
        inputText = ""

        // Process response on-device
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let result = DaylightFinancialAssistantEngine.shared.generateResponse(for: text, store: store)
            let assistantMsg = AssistantMessage(isUser: false, text: result.text, payload: result.payload)
            withAnimation(.easeOut(duration: 0.25)) {
                messages.append(assistantMsg)
            }
        }
    }
}
