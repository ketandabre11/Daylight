import SwiftUI
import UniformTypeIdentifiers

public struct ExportTextFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, .plainText] }
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let str = String(data: data, encoding: .utf8) {
            self.text = str
        } else {
            self.text = ""
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Screen I: In-App Notification Centre & Preferences Sheet

public struct NotificationsSheetView: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Live Calculated Evening Summary") {
                    let previewPayload = DaylightNotificationScheduler.buildDailyEveningSummary(
                        tenantId: store.activeTenantId,
                        referenceDate: store.referenceDate,
                        timeZoneId: store.profile.timeZoneId,
                        summary: store.allowanceSummary,
                        preferences: store.notificationPreferences
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            DaylightBadge("Calculated Live", icon: "sparkles", tone: .positive)
                            Spacer()
                            Text("Scheduled \(DaylightNotificationScheduler.effectiveSummaryHour(requestedHour: store.notificationPreferences.dailySummaryHour)):00 (\(store.profile.timeZoneId))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(previewPayload.title)
                            .font(.subheadline.weight(.semibold))
                        Text(previewPayload.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Refresh & Sync OS Notification Schedule") {
                            store.refreshDailyNotificationsAndSchedule()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(DaylightTheme.accent)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }

                Section("Recent Alerts & Reminders (Tap to Open Screen)") {
                    if store.notifications.isEmpty {
                        Text("No notifications right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.notifications) { item in
                            Button {
                                navigateForNotification(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        DaylightBadge(item.categoryTag, icon: "bell.fill", tone: item.isRead ? .neutral : .warning)
                                        Spacer()
                                        Text(AustralianDateHelper.formatDateTime(item.createdAt, timeZoneId: store.profile.timeZoneId))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(
                                        store.notificationPreferences.hideExactAmountsInPreviews
                                            ? "Exact amounts hidden for lock-screen privacy. Open \(BrandConfig.appName) to view details."
                                            : item.body
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Notification & Privacy Preferences") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Evening Summary Time")
                                .font(.subheadline)
                            Text("Quiet hours (10 PM – 7 AM) protected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let currentHour = DaylightNotificationScheduler.effectiveSummaryHour(
                            requestedHour: store.notificationPreferences.dailySummaryHour
                        )
                        Menu {
                            ForEach([18, 19, 20, 21], id: \.self) { hour in
                                let labelText = "\(hour - 12):00 PM"
                                Button {
                                    var p = store.notificationPreferences
                                    p.dailySummaryHour = DaylightNotificationScheduler.effectiveSummaryHour(requestedHour: hour)
                                    store.updateNotificationPreferences(p)
                                } label: {
                                    if hour == currentHour {
                                        Label(labelText, systemImage: "checkmark")
                                    } else {
                                        Text(labelText)
                                    }
                                }
                            }
                        } label: {
                            DaylightDropdownPill("\(currentHour - 12):00 PM", icon: "clock")
                        }
                    }

                    Toggle(
                        "Hide Exact Dollar Amounts in Notification Previews",
                        isOn: Binding(
                            get: { store.notificationPreferences.hideExactAmountsInPreviews },
                            set: { val in
                                var p = store.notificationPreferences
                                p.hideExactAmountsInPreviews = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
                    Toggle(
                        "Daily Safe-to-Spend Summary",
                        isOn: Binding(
                            get: { store.notificationPreferences.dailySummaryEnabled },
                            set: { val in
                                var p = store.notificationPreferences
                                p.dailySummaryEnabled = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
                    Toggle(
                        "Budget Threshold Alerts (80% & 100%)",
                        isOn: Binding(
                            get: { store.notificationPreferences.budgetThresholdAlertsEnabled },
                            set: { val in
                                var p = store.notificationPreferences
                                p.budgetThresholdAlertsEnabled = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
                    Toggle(
                        "Upcoming Bill Reminders",
                        isOn: Binding(
                            get: { store.notificationPreferences.upcomingBillRemindersEnabled },
                            set: { val in
                                var p = store.notificationPreferences
                                p.upcomingBillRemindersEnabled = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
                    Toggle(
                        "Payday & Cycle Reset Reminders",
                        isOn: Binding(
                            get: { store.notificationPreferences.paydayRemindersEnabled },
                            set: { val in
                                var p = store.notificationPreferences
                                p.paydayRemindersEnabled = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
                }
            }
            .navigationTitle("Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mark All Read") {
                        store.markAllNotificationsRead()
                    }
                    .disabled(store.unreadNotificationCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func navigateForNotification(_ item: AppNotification) {
        switch item.categoryTag {
        case "budget_alert":
            store.selectedSection = .budgets
        case "upcoming_bill":
            store.selectedSection = .bills
        case "daily_summary":
            store.selectedSection = .overview
        default:
            store.selectedSection = .transactions
        }
        dismiss()
    }
}

// MARK: - Screen J: Settings, Privacy, Data Export & Compliance View

public struct SettingsPrivacyView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public enum ExportDateRangeOption: String, CaseIterable, Identifiable {
        case all = "All Time"
        case currentPeriod = "This Pay Cycle"
        case currentFY = "This Financial Year"
        case last90Days = "Last 90 Days"

        public var id: String { rawValue }
    }

    @State private var selectedExportDateRange: ExportDateRangeOption = .all
    @State private var exportedDocumentTitle: String = ""
    @State private var exportedDocumentContent: String = ""
    @State private var showingExportSheet: Bool = false
    @State private var showingSystemFileExporter: Bool = false
    @State private var exportFileDocument = ExportTextFileDocument(text: "")
    @State private var exportDefaultFilename: String = "Daylight_Money_Export.csv"
    @State private var showingDeleteConfirmation: Bool = false
    @State private var showingArchitectureDocsSheet: Bool = false
    @State private var showingAuditLogSheet: Bool = false

    @State private var preferredNameDraft: String = ""
    @State private var takeHomeDollarsDraft: String = ""
    @State private var savingsDollarsDraft: String = ""

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                accountHeaderCard
                payCycleAndProfileCard
                workspaceToolsAndAppearanceCard
                dataExportAndPrivacyCard
                dangerZoneCard
            }
            .padding(DaylightTheme.Spacing.md)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(DaylightTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear {
            syncDrafts()
        }
        .onChange(of: store.isDemoMode) { _, _ in
            syncDrafts()
        }
        .onChange(of: store.activeTenantId) { _, _ in
            syncDrafts()
        }
        .onChange(of: store.profile.preferredName) { _, _ in
            syncDrafts()
        }
        .onChange(of: store.authenticatedSession?.fullName) { _, _ in
            syncDrafts()
        }
        .sheet(isPresented: $showingExportSheet) {
            NavigationStack {
                ScrollView {
                    Text(exportedDocumentContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(exportedDocumentTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingExportSheet = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingArchitectureDocsSheet) {
            ArchitectureAndComplianceInspectorSheet()
        }
        .sheet(isPresented: $showingAuditLogSheet) {
            auditAndImportHistorySheet
        }
        .fileExporter(
            isPresented: $showingSystemFileExporter,
            document: exportFileDocument,
            contentType: exportDefaultFilename.hasSuffix(".json") ? .json : .commaSeparatedText,
            defaultFilename: exportDefaultFilename
        ) { result in
            if case .success = result {
                store.statusBannerMessage = "Saved \(exportDefaultFilename) safely."
            }
        }
        .confirmationDialog(
            store.isDemoMode ? "Reset Synthetic Demo Workspace?" : "Permanently Delete Personal Workspace Data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(store.isDemoMode ? "Reset Demo Data" : "Permanently Delete All My Data", role: .destructive) {
                store.deleteCurrentWorkspaceData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                store.isDemoMode
                    ? "This will restore the synthetic Australian demo dataset to its initial state."
                    : "This permanently erases all accounts, transactions, budgets, savings goals, and audit records from your personal workspace."
            )
        }
    }

    private var resolvedDisplayName: String {
        let profileName = store.profile.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = store.authenticatedSession?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isRealUserSession = store.authenticatedSession != nil && store.authenticatedSession?.userId != "demo_user_au"

        if isRealUserSession && !sessionName.isEmpty && (profileName.isEmpty || profileName == "Alex" || profileName == "Friend") {
            return sessionName
        }
        if !profileName.isEmpty {
            return profileName
        }
        return sessionName.isEmpty ? "Account" : sessionName
    }

    private func syncDrafts() {
        preferredNameDraft = resolvedDisplayName == "Account" ? "" : resolvedDisplayName
        takeHomeDollarsDraft = String(format: "%.2f", Double(store.profile.typicalTakeHomePayCents) / 100.0)
        savingsDollarsDraft = String(format: "%.2f", Double(store.profile.savingsTargetPerPeriodCents) / 100.0)
    }

    // MARK: - 1. Account & Session Card

    private var accountHeaderCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: store.isDemoMode ? "sparkles.rectangle.stack.fill" : "person.crop.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(DaylightTheme.forestGreen)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(DaylightTheme.forestGreen.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resolvedDisplayName)
                                .font(.headline)
                            DaylightBadge(
                                store.isDemoMode ? "Demo" : "Personal",
                                icon: store.isDemoMode ? "sparkles" : "lock.fill",
                                tone: store.isDemoMode ? .warning : .positive
                            )
                        }
                        Text(store.authenticatedSession?.email ?? "Synthetic Australian Demo Workspace")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        store.switchWorkspaceMode(toDemo: !store.isDemoMode)
                    } label: {
                        Label(
                            store.isDemoMode ? "Switch to Personal" : "Try Demo Mode",
                            systemImage: "arrow.left.arrow.right"
                        )
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task {
                            await store.logoutAccount()
                        }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(DaylightTheme.cautionRed)
                    .accessibilityIdentifier("settings_logout_button")
                }
            }
        }
    }

    // MARK: - 2. Profile & Pay Cycle Card

    private var payCycleAndProfileCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profile & Pay Cycle")
                            .font(.headline)
                        Text("AUD ($) • Australian Financial Year (1 Jul – 30 Jun)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Setup Wizard") {
                        store.showingOnboardingSheet = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DaylightTheme.forestGreen)
                }

                Divider()

                VStack(spacing: 12) {
                    labeledFieldRow("Preferred Name") {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(resolvedDisplayName)
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
                        .accessibilityLabel("Preferred Name: \(resolvedDisplayName) (Registered credential, non-editable)")
                    }

                    labeledFieldRow("Time Zone") {
                        let currentTZ = AustralianTimeZone(rawValue: store.profile.timeZoneId) ?? .sydney
                        Menu {
                            ForEach(AustralianTimeZone.allCases) { tz in
                                Button {
                                    var p = store.profile
                                    p.timeZoneId = tz.rawValue
                                    try? store.updateProfile(p)
                                } label: {
                                    if tz == currentTZ {
                                        Label(tz.shortLabel, systemImage: "checkmark")
                                    } else {
                                        Text(tz.shortLabel)
                                    }
                                }
                            }
                        } label: {
                            compactDropdownLabel(currentTZ.shortLabel)
                        }
                    }

                    labeledFieldRow("Pay Cycle") {
                        Menu {
                            ForEach(PayFrequency.allCases) { f in
                                Button {
                                    var p = store.profile
                                    p.payFrequency = f
                                    try? store.updateProfile(p)
                                } label: {
                                    if f == store.profile.payFrequency {
                                        Label(f.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(f.displayName)
                                    }
                                }
                            }
                        } label: {
                            compactDropdownLabel(store.profile.payFrequency.displayName)
                        }
                    }

                    labeledFieldRow("Take-Home Pay (AUD)") {
                        TextField("0.00", text: $takeHomeDollarsDraft)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    labeledFieldRow("Savings Target (AUD)") {
                        TextField("0.00", text: $savingsDollarsDraft)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Button {
                    var p = store.profile
                    p.preferredName = resolvedDisplayName
                    if let payCents = AustralianMoneyFormatter.parseToCents(takeHomeDollarsDraft), payCents >= 0 {
                        p.typicalTakeHomePayCents = payCents
                    }
                    if let savCents = AustralianMoneyFormatter.parseToCents(savingsDollarsDraft), savCents >= 0 {
                        p.savingsTargetPerPeriodCents = savCents
                    }
                    try? store.updateProfile(p)
                    store.statusBannerMessage = "Saved profile & pay-cycle settings."
                } label: {
                    Text("Save Changes")
                }
                .buttonStyle(DaylightPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    private func labeledFieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
    }

    private func compactDropdownLabel(_ text: String) -> some View {
        DaylightDropdownPill(text)
    }

    // MARK: - 3. Workspace Tools & Appearance Card

    private var workspaceToolsAndAppearanceCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preferences & Tools")
                    .font(.headline)

                HStack {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline)
                    Spacer()
                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { store.profile.themePreference },
                            set: { pref in
                                var p = store.profile
                                p.themePreference = pref
                                try? store.updateProfile(p)
                            }
                        )
                    ) {
                        ForEach(AppThemePreference.allCases) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 210)
                }

                Divider()

                settingsNavigationRow(
                    title: "Manage Categories",
                    subtitle: "Create, rename, or archive custom categories",
                    icon: "tag.fill"
                ) {
                    store.showingCategoriesManagerSheet = true
                }

                Divider()

                settingsNavigationRow(
                    title: "Notifications & Quiet Hours",
                    subtitle: "Daily summary time and lock-screen privacy",
                    icon: "bell.badge.fill"
                ) {
                    store.showingNotificationsSheet = true
                }

                Divider()

                settingsNavigationRow(
                    title: "Accounts & Open Banking (CDR)",
                    subtitle: "\(store.accounts.count) linked or manual account(s)",
                    icon: "building.columns.fill"
                ) {
                    store.selectedSection = .accounts
                }

                Divider()

                settingsNavigationRow(
                    title: "Bills & Subscriptions",
                    subtitle: "Fixed commitments and upcoming reminders",
                    icon: "calendar.badge.clock"
                ) {
                    store.selectedSection = .bills
                }

                Divider()

                settingsNavigationRow(
                    title: "Spending Insights",
                    subtitle: "Category trends and cashflow breakdown",
                    icon: "chart.bar.xaxis"
                ) {
                    store.selectedSection = .insights
                }
            }
        }
    }

    private func settingsNavigationRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(DaylightTheme.forestGreen)
                    .frame(width: 30, height: 30)
                    .background(DaylightTheme.forestGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Data Export, Audit & Privacy Card

    private var dataExportAndPrivacyCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data & Privacy")
                    .font(.headline)

                HStack {
                    Text("Export Range")
                        .font(.subheadline)
                    Spacer()
                    Menu {
                        ForEach(ExportDateRangeOption.allCases) { opt in
                            Button {
                                selectedExportDateRange = opt
                            } label: {
                                if opt == selectedExportDateRange {
                                    Label(opt.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(opt.rawValue)
                                }
                            }
                        }
                    } label: {
                        compactDropdownLabel(selectedExportDateRange.rawValue)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        let bounds = resolvedExportBounds()
                        let csvText = store.exportTransactionsAsSanitizedCSV(fromDate: bounds.from, toDate: bounds.to)
                        exportFileDocument = ExportTextFileDocument(text: csvText)
                        exportDefaultFilename = "Daylight_Transactions_\(AustralianDateHelper.formatISODate(store.referenceDate, timeZoneId: store.profile.timeZoneId)).csv"
                        showingSystemFileExporter = true
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.forestGreen)

                    Button {
                        let bounds = resolvedExportBounds()
                        let csvText = store.exportTransactionsAsSanitizedCSV(fromDate: bounds.from, toDate: bounds.to)
                        exportedDocumentTitle = "Transactions CSV (\(selectedExportDateRange.rawValue))"
                        exportedDocumentContent = csvText
                        showingExportSheet = true
                    } label: {
                        Label("Preview CSV", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                settingsNavigationRow(
                    title: "Export Full Workspace JSON",
                    subtitle: "Complete portable archive of your workspace",
                    icon: "curlybraces"
                ) {
                    exportedDocumentTitle = "Workspace Archive (\(store.activeTenantId))"
                    exportedDocumentContent = store.exportWorkspaceAsJSON()
                    showingExportSheet = true
                }

                Divider()

                settingsNavigationRow(
                    title: "Activity & Import History",
                    subtitle: "\(store.auditEvents.count) audit events • \(store.importJobs.count) statement imports",
                    icon: "clock.arrow.circlepath"
                ) {
                    showingAuditLogSheet = true
                }

                Divider()

                settingsNavigationRow(
                    title: "Australian Privacy & Security Specs",
                    subtitle: "Privacy Act 1988 (Cth), CDR & SQLite architecture",
                    icon: "checkmark.shield.fill"
                ) {
                    showingArchitectureDocsSheet = true
                }
            }
        }
    }

    private func resolvedExportBounds() -> (from: Date?, to: Date?) {
        let cal = AustralianDateHelper.calendar(for: store.profile.timeZoneId)
        switch selectedExportDateRange {
        case .all:
            return (nil, nil)
        case .currentPeriod:
            return (store.allowanceSummary.periodStart, store.allowanceSummary.periodEnd)
        case .currentFY:
            let fy = AustralianDateHelper.financialYearBounds(for: store.referenceDate, timeZoneId: store.profile.timeZoneId)
            return (fy.start, fy.end)
        case .last90Days:
            let ninetyAgo = cal.date(byAdding: .day, value: -90, to: store.referenceDate)
            return (ninetyAgo, store.referenceDate)
        }
    }

    // MARK: - 5. Danger Zone Card

    private var dangerZoneCard: some View {
        DaylightCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isDemoMode ? "Reset Demo Data" : "Erase Personal Workspace")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.cautionRed)
                    Text(
                        store.isDemoMode
                            ? "Restore synthetic demo transactions and budgets to defaults."
                            : "Permanently delete all local accounts, transactions, and budgets."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text(store.isDemoMode ? "Reset" : "Delete Data")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(DaylightTheme.cautionRed)
            }
        }
    }

    // MARK: - Activity & Import History Modal Sheet

    private var auditAndImportHistorySheet: some View {
        NavigationStack {
            List {
                if !store.importJobs.isEmpty {
                    Section("Statement Imports") {
                        ForEach(store.importJobs) { job in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.fileName)
                                    .font(.subheadline.weight(.semibold))
                                Text("Imported: \(job.importedCount) • Duplicates skipped: \(job.duplicateSkippedCount) • Rejected: \(job.rejectedCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Workspace Activity Log (\(store.auditEvents.count))") {
                    if store.auditEvents.isEmpty {
                        Text("No activity recorded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.auditEvents.prefix(30)) { ev in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ev.action)
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(DaylightTheme.forestGreen)
                                    Spacer()
                                    Text(AustralianDateHelper.formatDateTime(ev.createdAt, timeZoneId: store.profile.timeZoneId))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(ev.summary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Activity & Imports")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingAuditLogSheet = false }
                }
            }
        }
    }
}
