import SwiftUI

public struct OnboardingView: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentStep: Int = 0
    @State private var preferredName: String = ""
    @State private var selectedTimeZone: AustralianTimeZone = .sydney
    @State private var employmentType: EmploymentIncomeType = .salariedEmployee
    @State private var payFrequency: PayFrequency = .fortnightly
    @State private var takeHomePayDollars: String = "3250.00"
    @State private var nextPayDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var fixedExpensesDollars: String = "1150.00"
    @State private var savingsTargetDollars: String = "500.00"
    @State private var budgetingMethod: BudgetingMethod = .payCycle
    @State private var validationMessage: String? = nil

    public init(store: DaylightStore) {
        self.store = store
    }

    private var parsedTakeHomeCents: MoneyCents {
        max(0, AustralianMoneyFormatter.parseToCents(takeHomePayDollars) ?? 0)
    }

    private var parsedFixedCents: MoneyCents {
        max(0, AustralianMoneyFormatter.parseToCents(fixedExpensesDollars) ?? 0)
    }

    private var parsedSavingsCents: MoneyCents {
        max(0, AustralianMoneyFormatter.parseToCents(savingsTargetDollars) ?? 0)
    }

    private var previewFlexiblePoolCents: MoneyCents {
        max(0, parsedTakeHomeCents - parsedFixedCents - parsedSavingsCents)
    }

    private var previewDailyAllowanceCents: MoneyCents {
        let days = Int64(max(1, payFrequency.nominalPeriodDays))
        return previewFlexiblePoolCents / days
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                    headerProgress
                    stepContent
                    livePreviewCard
                    if let validationMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(validationMessage)
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(DaylightTheme.cautionRed)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm)
                                .fill(DaylightTheme.cautionRed.opacity(0.12))
                        )
                    }
                    navigationButtons
                }
                .padding(DaylightTheme.Spacing.lg)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Welcome to \(BrandConfig.appName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip for Now") {
                        applyConfiguration()
                    }
                }
            }
            .onAppear {
                let p = store.profile
                let sessionName = store.authenticatedSession?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                preferredName = p.preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sessionName : p.preferredName
                selectedTimeZone = AustralianTimeZone(rawValue: p.timeZoneId) ?? .sydney
                employmentType = p.employmentType
                payFrequency = p.payFrequency
                takeHomePayDollars = String(format: "%.2f", Double(p.typicalTakeHomePayCents) / 100.0)
                nextPayDate = p.nextPayDate
                let fixedSum = store.fixedCommitments.reduce(MoneyCents(0)) { $0 + $1.amountCents }
                if fixedSum > 0 {
                    fixedExpensesDollars = String(format: "%.2f", Double(fixedSum) / 100.0)
                }
                savingsTargetDollars = String(format: "%.2f", Double(p.savingsTargetPerPeriodCents) / 100.0)
                budgetingMethod = p.preferredBudgetingMethod
            }
        }
    }

    private var headerProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DaylightBadge("Australian Edition • AUD ($)", icon: "globe.asia.australia.fill", tone: .neutral)
                Spacer()
                Text("Step \(currentStep + 1) of 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? DaylightTheme.accent : Color.secondary.opacity(0.25))
                        .frame(height: 6)
                }
            }

            Text(BrandConfig.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            DaylightCard {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                    Text("1. About You & Your Australian Locale")
                        .font(.headline)

                    Text("No bank password or immediate account linking is required. All settings can be changed at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Preferred Name")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(preferredName.isEmpty ? (store.authenticatedSession?.fullName ?? "Alex") : preferredName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                        .accessibilityLabel("Preferred Name: \(preferredName)")
                    }

                    HStack {
                        Text("State / Time Zone")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Menu {
                            ForEach(AustralianTimeZone.allCases) { tz in
                                Button {
                                    selectedTimeZone = tz
                                } label: {
                                    if tz == selectedTimeZone {
                                        Label(tz.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(tz.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(selectedTimeZone.shortLabel, icon: "globe.asia.australia.fill")
                        }
                    }

                    HStack {
                        Text("Income Arrangement")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Menu {
                            ForEach(EmploymentIncomeType.allCases) { item in
                                Button {
                                    employmentType = item
                                } label: {
                                    if item == employmentType {
                                        Label(item.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(item.displayName)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill(employmentType.displayName, icon: "briefcase")
                        }
                    }
                }
            }

        case 1:
            DaylightCard {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                    Text("2. Pay Cycle & Take-Home Income")
                        .font(.headline)

                    Text("Whether you're paid weekly, fortnightly, monthly, or have irregular ABN/casual income, Daylight aligns your safe daily allowance to your rhythm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pay Frequency")
                            .font(.subheadline.weight(.medium))
                        Picker("Pay Frequency", selection: $payFrequency) {
                            ForEach(PayFrequency.allCases) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Typical Net Take-Home Pay per \(payFrequency.displayName) (AUD)")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. 3250.00", text: $takeHomePayDollars)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityLabel("Typical Take Home Pay in Australian Dollars")
                    }

                    DatePicker(
                        "Next Expected Payday",
                        selection: $nextPayDate,
                        displayedComponents: [.date]
                    )
                    .font(.subheadline.weight(.medium))
                }
            }

        default:
            DaylightCard {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                    Text("3. Commitments, Savings & Method")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Known Fixed Bills per \(payFrequency.displayName) (Rent/Mortgage, Utilities, Insurance)")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. 1150.00", text: $fixedExpensesDollars)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planned Savings Target per \(payFrequency.displayName) (Optional)")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. 500.00", text: $savingsTargetDollars)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Budgeting Method")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Menu {
                                ForEach(BudgetingMethod.allCases) { method in
                                    Button {
                                        budgetingMethod = method
                                    } label: {
                                        if method == budgetingMethod {
                                            Label(method.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(method.displayName)
                                        }
                                    }
                                }
                            } label: {
                                DaylightDropdownPill(budgetingMethod.displayName, icon: "slider.horizontal.3")
                            }
                        }
                        Text(budgetingMethod.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var livePreviewCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "function")
                        .foregroundStyle(DaylightTheme.accent)
                    Text("How Your Daily Safe-to-Spend Is Calculated")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(payFrequency.nominalPeriodDays)-day cycle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                calculationRow("Take-home income", cents: parsedTakeHomeCents, isPositive: true)
                calculationRow("Less fixed expenses & bills", cents: -parsedFixedCents, isPositive: false)
                calculationRow("Less planned savings", cents: -parsedSavingsCents, isPositive: false)

                Divider()

                HStack {
                    Text("Remaining flexible budget")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(AustralianMoneyFormatter.format(cents: previewFlexiblePoolCents))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }

                HStack {
                    Text("Baseline daily safe-to-spend (÷ \(payFrequency.nominalPeriodDays) days)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.accent)
                    Spacer()
                    Text("\(AustralianMoneyFormatter.format(cents: previewDailyAllowanceCents)) / day")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DaylightTheme.positive)
                }
            }
        }
    }

    private func calculationRow(_ label: String, cents: MoneyCents, isPositive: Bool) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(AustralianMoneyFormatter.format(cents: cents, showPlusForPositive: isPositive))
                .font(.footnote.weight(.medium))
                .monospacedDigit()
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if currentStep < 2 {
                    withAnimation { currentStep += 1 }
                } else {
                    applyConfiguration()
                }
            } label: {
                Text(currentStep < 2 ? "Continue" : "Finish Setup & View Dashboard")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(DaylightTheme.accent)
        }
    }

    private func applyConfiguration() {
        guard AustralianMoneyFormatter.parseToCents(takeHomePayDollars) != nil else {
            validationMessage = "Please enter a valid AUD dollar amount for your take-home pay (e.g. 3250.00)."
            return
        }
        validationMessage = nil
        store.completeOnboarding(
            preferredName: preferredName,
            timeZoneId: selectedTimeZone.rawValue,
            employmentType: employmentType,
            payFrequency: payFrequency,
            takeHomePayCents: parsedTakeHomeCents,
            nextPayDate: nextPayDate,
            fixedExpensesCents: parsedFixedCents,
            savingsTargetCents: parsedSavingsCents,
            budgetingMethod: budgetingMethod
        )
        dismiss()
    }
}
