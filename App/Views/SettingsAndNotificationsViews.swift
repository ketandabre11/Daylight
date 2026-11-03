import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var authorizationState: DaylightNotificationScheduler.AuthorizationState = .notDetermined

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

                Section("System Permission") {
                    HStack {
                        Text("iOS notification access")
                        Spacer()
                        Text(permissionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(permissionStateColor)
                    }
                    if authorizationState == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                authorizationState = (try? await DaylightNotificationScheduler.requestAuthorization())
                                    ?? .denied
                                store.refreshDailyNotificationsAndSchedule()
                            }
                        }
                    } else if authorizationState == .denied || authorizationState == .restricted {
                        Button("Open iOS Notification Settings") {
                            #if canImport(UIKit)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                            #endif
                        }
                    }
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
                        "Notifications",
                        isOn: Binding(
                            get: { store.notificationPreferences.notificationsEnabled },
                            set: { val in
                                var p = store.notificationPreferences
                                p.notificationsEnabled = val
                                store.updateNotificationPreferences(p)
                            }
                        )
                    )
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
                    Text("Payday, recurring-change, and unusual-spending alerts are not available in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                authorizationState = await DaylightNotificationScheduler.authorizationState()
            }
            .onAppear {
                Task {
                    authorizationState = await DaylightNotificationScheduler.authorizationState()
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

    private var permissionLabel: String {
        switch authorizationState {
        case .notDetermined: return "Not set"
        case .authorized: return "Allowed"
        case .provisional: return "Quietly allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .ephemeral: return "Temporary"
        case .unavailable: return "Unavailable"
        }
    }

    private var permissionStateColor: Color {
        switch authorizationState {
        case .authorized, .provisional: return .green
        case .denied, .restricted: return .red
        default: return .secondary
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
    @State private var showingProfilePhotoSheet: Bool = false

    private enum ProfileField: Hashable {
        case takeHomePay
        case savingsTarget
    }

    @State private var preferredNameDraft: String = ""
    @State private var takeHomeDollarsDraft: String = ""
    @State private var savingsDollarsDraft: String = ""
    @State private var saveFeedbackMessage: String? = nil
    @State private var saveErrorMessage: String? = nil
    @State private var didJustSave: Bool = false
    @FocusState private var focusedProfileField: ProfileField?

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
        .scrollDismissesKeyboard(.interactively)
        .background(DaylightAtmosphericBackground())
        .reportsDaylightScrollPosition()
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
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
        .onChange(of: store.profile.typicalTakeHomePayCents) { _, _ in
            syncDrafts()
        }
        .onChange(of: store.profile.savingsTargetPerPeriodCents) { _, _ in
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
        .sheet(isPresented: $showingProfilePhotoSheet) {
            ProfilePhotoPickerSheet(
                initialImageData: store.profile.avatarImageData,
                displayName: resolvedDisplayName
            ) { updatedImage in
                do {
                    try store.updateProfileAvatar(imageData: updatedImage)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        saveFeedbackMessage = updatedImage == nil ? "Profile picture removed." : "Profile picture updated."
                    }
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } catch {
                    saveErrorMessage = error.localizedDescription
                }
            }
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
                    // Avatar with interactive edit badge (Single relevant position)
                    Button {
                        dismissKeyboard()
                        showingProfilePhotoSheet = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            DaylightAvatarView(
                                avatarImageData: store.profile.avatarImageData,
                                name: resolvedDisplayName,
                                size: 58,
                                isDemo: store.isDemoMode,
                                showBorder: true,
                                borderColor: DaylightTheme.accent.opacity(0.6)
                            )

                            // Subtle edit / camera badge indicator
                            Circle()
                                .fill(DaylightTheme.accent)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(DaylightTheme.surface(for: colorScheme), lineWidth: 2)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change profile picture")
                    .accessibilityHint("Opens options to upload a photo, take a picture, or select an Australian avatar preset.")

                    VStack(alignment: .leading, spacing: 4) {
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
                            .lineLimit(1)

                        Button {
                            dismissKeyboard()
                            showingProfilePhotoSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: store.profile.avatarImageData == nil ? "plus.circle.fill" : "camera.fill")
                                    .font(.caption2.weight(.semibold))
                                Text(store.profile.avatarImageData == nil ? "Add Photo" : "Change Photo")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(DaylightTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(DaylightTheme.accent.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityLabel("Change profile picture")
                    }

                    Spacer()
                }

                Divider()

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

    // MARK: - 2. Profile & Pay Cycle Card

    private var payCycleAndProfileCard: some View {
        DaylightCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profile & Pay Cycle")
                            .font(.headline)
                        Text("AUD ($) • AFY (1 Jul – 30 Jun)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Setup") {
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
                                    dismissKeyboard()
                                    var p = store.profile
                                    p.tenantId = store.activeTenantId
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
                                    dismissKeyboard()
                                    // Rescales pay & savings so annual income (and daily allowance) stay consistent.
                                    try? store.changePayFrequency(to: f)
                                    syncDrafts()
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

                    labeledFieldRow("Take-Home Pay per \(store.profile.payFrequency.displayName) (AUD)") {
                        TextField("0.00", text: $takeHomeDollarsDraft)
                            .focused($focusedProfileField, equals: .takeHomePay)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: takeHomeDollarsDraft) { _, _ in
                                saveErrorMessage = nil
                            }
                    }

                    labeledFieldRow("Savings Target per \(store.profile.payFrequency.displayName) (AUD)") {
                        TextField("0.00", text: $savingsDollarsDraft)
                            .focused($focusedProfileField, equals: .savingsTarget)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: savingsDollarsDraft) { _, _ in
                                saveErrorMessage = nil
                            }
                    }
                }

                if let saveErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DaylightTheme.cautionRed)
                        Text(saveErrorMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DaylightTheme.cautionRed)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm, style: .continuous)
                            .fill(DaylightTheme.cautionRed.opacity(0.10))
                    )
                }

                if let saveFeedbackMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DaylightTheme.positive)
                        Text(saveFeedbackMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm, style: .continuous)
                            .fill(DaylightTheme.positive.opacity(0.12))
                    )
                }

                Button {
                    saveProfileChanges()
                } label: {
                    HStack(spacing: 6) {
                        if didJustSave {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(didJustSave ? "Changes Saved" : "Save Changes")
                    }
                }
                .buttonStyle(DaylightPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    private func dismissKeyboard() {
        focusedProfileField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private func saveProfileChanges() {
        dismissKeyboard()
        saveErrorMessage = nil

        let trimmedPay = takeHomeDollarsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPayCents: MoneyCents? = trimmedPay.isEmpty
            ? 0
            : AustralianMoneyFormatter.parseToCents(trimmedPay)
        guard let payCents = parsedPayCents, payCents >= 0 else {
            saveErrorMessage = "Enter a valid non-negative dollar amount for Take-Home Pay."
            return
        }

        let trimmedSavings = savingsDollarsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSavingsCents: MoneyCents? = trimmedSavings.isEmpty
            ? 0
            : AustralianMoneyFormatter.parseToCents(trimmedSavings)
        guard let savCents = parsedSavingsCents, savCents >= 0 else {
            saveErrorMessage = "Enter a valid non-negative dollar amount for Savings Target."
            return
        }

        var p = store.profile
        p.tenantId = store.activeTenantId
        p.preferredName = resolvedDisplayName
        p.typicalTakeHomePayCents = payCents
        p.savingsTargetPerPeriodCents = savCents

        do {
            try store.updateProfile(p)
            syncDrafts()
            store.statusBannerMessage = "Saved profile & pay-cycle settings."
            withAnimation(.easeInOut(duration: 0.2)) {
                saveFeedbackMessage = "Saved \(store.profile.payFrequency.displayName.lowercased()) pay (\(AustralianMoneyFormatter.format(cents: payCents))) and savings target (\(AustralianMoneyFormatter.format(cents: savCents)))."
                didJustSave = true
            }
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 0.2)) {
                    didJustSave = false
                }
            }
        } catch {
            saveErrorMessage = "Unable to save settings: \(error.localizedDescription)"
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

                    let currentPreference = store.profile.themePreference
                    Menu {
                        ForEach(AppThemePreference.allCases) { pref in
                            Button {
                                var profile = store.profile
                                profile.themePreference = pref
                                try? store.updateProfile(profile)
                            } label: {
                                if pref == currentPreference {
                                    Label(pref.displayName, systemImage: "checkmark")
                                } else {
                                    Text(pref.displayName)
                                }
                            }
                        }
                    } label: {
                        DaylightDropdownPill(currentPreference.displayName, icon: "paintbrush")
                    }
                    .accessibilityLabel("Appearance")
                    .accessibilityValue(currentPreference.displayName)
                }

                Divider()

                settingsNavigationRow(
                    title: "How Is Safe-to-Spend Calculated?",
                    subtitle: "See income, bills, savings, spending, and remaining days",
                    icon: "function"
                ) {
                    store.showingCalculationExplainer = true
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
                    title: "Notifications",
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
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: DaylightTheme.Spacing.sm) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3)
                        .foregroundStyle(DaylightTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(DaylightTheme.accent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data & Privacy")
                            .font(.headline)
                        Text("Review, export & organise your finances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: DaylightTheme.Spacing.xs)
                    exportPrivacyBadge
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transactions to export")
                            .font(.subheadline)
                        Text("Transactions within your selected date range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                        DaylightDropdownPill(selectedExportDateRange.rawValue, icon: "calendar")
                    }
                    .accessibilityLabel("Transactions to export")
                    .accessibilityValue(selectedExportDateRange.rawValue)
                }

                HStack(spacing: DaylightTheme.Spacing.xs) {
                    Button {
                        let bounds = resolvedExportBounds()
                        let csvText = store.exportTransactionsAsSanitizedCSV(fromDate: bounds.from, toDate: bounds.to)
                        exportFileDocument = ExportTextFileDocument(text: csvText)
                        exportDefaultFilename = "Daylight_Transactions_\(AustralianDateHelper.formatISODate(store.referenceDate, timeZoneId: store.profile.timeZoneId)).csv"
                        showingSystemFileExporter = true
                    } label: {
                        Label("Save CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.primaryAction)
                    .accessibilityHint("Choose a secure location before saving your export.")

                    Button {
                        let bounds = resolvedExportBounds()
                        let csvText = store.exportTransactionsAsSanitizedCSV(fromDate: bounds.from, toDate: bounds.to)
                        exportedDocumentTitle = "Transactions CSV (\(selectedExportDateRange.rawValue))"
                        exportedDocumentContent = csvText
                        showingExportSheet = true
                    } label: {
                        Label("Review CSV", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Review export contents before saving or sharing.")
                }

                Divider()

                settingsNavigationRow(
                    title: "Review Full Workspace Archive",
                    subtitle: "Check the complete archive before saving or sharing it",
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
                    title: "Privacy & Security Information",
                    subtitle: "How your data, exports, and privacy settings are handled",
                    icon: "checkmark.shield.fill"
                ) {
                    showingArchitectureDocsSheet = true
                }
            }
        }
    }

    /// Compact capsule shown beside the "Data & Privacy" title.
    private var exportPrivacyBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption2)
            Text("Secure Exports")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DaylightTheme.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(DaylightTheme.warning.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Secure Exports")
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
                            : "Delete all accounts, & transactions."
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
