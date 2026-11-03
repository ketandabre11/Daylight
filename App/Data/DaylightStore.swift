import Foundation
import Observation
import SwiftUI

extension TransactionCategoryRecord {
    public var isSystem: Bool { isSystemDefault }
}

// MARK: - Tenant Workspace Container (Persisted to Disk)

public struct TenantWorkspaceSnapshot: Codable, Sendable {
    public var tenantId: String
    public var profile: UserProfile
    public var accounts: [FinancialAccount]
    public var consentRecords: [ConsentRecord]
    public var transactions: [TransactionRecord]
    public var merchantRules: [MerchantRule]
    public var fixedCommitments: [FixedCommitment]
    public var categoryBudgets: [CategoryBudget]
    public var recurringPredictions: [RecurringPaymentPrediction]
    public var savingsGoals: [SavingsGoal]
    public var notificationPreferences: NotificationPreferences
    public var notifications: [AppNotification]
    public var importJobs: [ImportJobRecord]
    public var auditEvents: [AuditEvent]
    public var processedIdempotencyKeys: [String]
}

public enum StoreAuthorizationError: LocalizedError, Equatable {
    case crossTenantAccessDenied(requestedTenant: String, activeTenant: String)
    case duplicateIdempotencyKey(String)
    case invalidSplitTotal(expectedCents: MoneyCents, actualCents: MoneyCents)
    case invalidTransactionDirection(kind: TransactionKind, direction: TransactionDirection)

    public var errorDescription: String? {
        switch self {
        case .crossTenantAccessDenied(let req, let active):
            return "Authorisation denied: resource belongs to tenant '\(req)' and cannot be accessed by '\(active)'."
        case .duplicateIdempotencyKey(let key):
            return "Duplicate request prevented by idempotency key '\(key)'."
        case .invalidSplitTotal(let expected, let actual):
            return "Split amounts (\(AustralianMoneyFormatter.format(cents: actual))) must equal the transaction total (\(AustralianMoneyFormatter.format(cents: expected)))."
        case .invalidTransactionDirection(let kind, let direction):
            return "\(kind.displayName) cannot use the \(direction == .debit ? "expense" : "income") direction."
        }
    }
}

// MARK: - DaylightStore (Authoritative Domain & Persistence Coordinator)

@Observable
@MainActor
public final class DaylightStore {
    public static let demoTenantId = "tenant_demo_au"
    public static let personalTenantId = "tenant_personal_au"

    /// Active authenticated user's isolated tenant ID (when signed in to a user account), or `personalTenantId` fallback.
    public private(set) var activeAuthenticatedTenantId: String? = nil

    /// Controls whether the user is viewing Synthetic Australian Demo Data or their isolated Personal Workspace.
    public var isDemoMode: Bool {
        didSet {
            if oldValue != isDemoMode {
                let previousTenant = oldValue ? Self.demoTenantId : (activeAuthenticatedTenantId ?? Self.personalTenantId)
                // Clear in-memory undo cache and deactivate old tenant session on workspace switch
                lastUndoDescription = nil
                previousTransactionsBackup = nil
                transactionCategoryDrilldown = nil
                customCategoryFilterId = nil
                try? sqliteDatabase?.clearActiveSessions(tenantId: previousTenant)
                if persistToDisk {
                    try? sqliteDatabase?.setMetadata(key: "active_workspace_mode", value: isDemoMode ? "demo" : "personal")
                }
                refreshWorkspaceCategories()
                recalculateDerivedState()
            }
        }
    }

    public var referenceDate: Date
    /// When true (default for live persisted sessions), `referenceDate` tracks the live system clock on recalculation and foreground entry.
    public var usesLiveClock: Bool

    private var demoWorkspace: TenantWorkspaceSnapshot
    private var personalWorkspace: TenantWorkspaceSnapshot
    private let persistToDisk: Bool
    public let sqliteDatabase: SQLitePersistenceDatabase?
    public let authService: any DaylightAuthenticationServiceProtocol
    private var notificationSyncTask: Task<Void, Never>?

    /// Authentication state & navigation route
    public var authState: AuthenticationState = .signedOut
    public var authNavigationRoute: AuthenticationRoute = .welcome
    public var authErrorMessage: String? = nil
    public var isAuthSubmitting: Bool = false

    /// Supports safe undo for the most recent transaction edit, deletion, or bulk categorisation.
    public var lastUndoDescription: String?
    private var previousTransactionsBackup: [TransactionRecord]?
    private var previousAccountsBackup: [FinancialAccount]?

    /// Derived state updated whenever underlying records change
    public private(set) var allowanceSummary: DailyAllowanceSummary
    public private(set) var categoryBudgetProgress: [CategoryBudgetProgress]
    public private(set) var activeInsights: [FinancialInsight]
    public private(set) var monthlySpendingAnalytics: MonthlySpendingAnalytics?
    public private(set) var workspaceCategories: [TransactionCategoryRecord] = []

    /// UI Navigation state
    public var selectedSection: AppNavigationSection = ProcessInfo.processInfo.arguments.contains("-settings") ? .settings : (ProcessInfo.processInfo.arguments.contains("-insights") ? .insights : .overview)
    public var showingCalculationExplainer: Bool = false
    public var showingStatementImporter: Bool = false
    public var showingNotificationsSheet: Bool = false
    public var showingOnboardingSheet: Bool = false
    public var showingCategoriesManagerSheet: Bool = false
    public var transactionCategoryDrilldown: AustralianCategory? = nil
    public var customCategoryFilterId: String? = nil
    public var statusBannerMessage: String? = nil
    public private(set) var persistenceErrorMessage: String? = nil

    public var activeTenantId: String {
        isDemoMode ? Self.demoTenantId : (activeAuthenticatedTenantId ?? Self.personalTenantId)
    }

    public var activeWorkspace: TenantWorkspaceSnapshot {
        get { isDemoMode ? demoWorkspace : personalWorkspace }
        set {
            if isDemoMode {
                demoWorkspace = newValue
            } else {
                personalWorkspace = newValue
            }
            recalculateDerivedState()
            saveWorkspacesIfNeeded()
        }
    }

    // Convenience accessors for active tenant
    public var profile: UserProfile { activeWorkspace.profile }
    public var accounts: [FinancialAccount] { activeWorkspace.accounts }
    public var consentRecords: [ConsentRecord] { activeWorkspace.consentRecords }
    public var transactions: [TransactionRecord] {
        activeWorkspace.transactions.sorted { $0.occurredAt > $1.occurredAt }
    }
    /// Transactions requiring user classification review (unclassified or low confidence < 0.70).
    public var unclassifiedTransactions: [TransactionRecord] {
        transactions.filter { $0.category == .cashAndUnclassified || $0.classificationConfidence < 0.70 }
    }
    public var merchantRules: [MerchantRule] { activeWorkspace.merchantRules }
    public var fixedCommitments: [FixedCommitment] { activeWorkspace.fixedCommitments }
    public var categoryBudgets: [CategoryBudget] { activeWorkspace.categoryBudgets }
    public var recurringPredictions: [RecurringPaymentPrediction] {
        activeWorkspace.recurringPredictions.filter { !$0.isDismissed }.sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }
    public var savingsGoals: [SavingsGoal] { activeWorkspace.savingsGoals }
    public var notificationPreferences: NotificationPreferences { activeWorkspace.notificationPreferences }
    public var notifications: [AppNotification] {
        activeWorkspace.notifications.sorted { $0.createdAt > $1.createdAt }
    }
    public var importJobs: [ImportJobRecord] {
        activeWorkspace.importJobs.sorted { $0.createdAt > $1.createdAt }
    }
    public var auditEvents: [AuditEvent] {
        activeWorkspace.auditEvents.sorted { $0.createdAt > $1.createdAt }
    }

    public var unreadNotificationCount: Int {
        activeWorkspace.notifications.filter { !$0.isRead }.count
    }

    /// Track dismissed duplicate transaction pair IDs for the active session and workspace
    public var dismissedDuplicatePairIds: Set<String> = []

    /// Detected potential and confirmed duplicate transactions in the active workspace
    public var duplicateCandidates: [DuplicateCandidateGroup] {
        DuplicateDetectionService.shared.detectDuplicates(
            transactions: activeWorkspace.transactions,
            dismissedPairIds: dismissedDuplicatePairIds
        )
    }

    /// Dismiss a duplicate alert so it is not shown again in this workspace
    public func dismissDuplicateCandidate(id: String) {
        dismissedDuplicatePairIds.insert(id)
    }

    public var authenticatedSession: AuthenticatedSession? {
        authState.currentSession
    }

    public var userDisplayName: String {
        let profileName = profile.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = authenticatedSession?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isRealSession = authenticatedSession != nil && authenticatedSession?.userId != "demo_user_au"

        if isRealSession && !sessionName.isEmpty && (profileName.isEmpty || profileName == "Alex" || profileName == "Friend") {
            return sessionName
        }
        if !profileName.isEmpty && profileName != "Alex" && profileName != "Friend" {
            return profileName
        }
        if !sessionName.isEmpty && sessionName != "Alex" {
            return sessionName
        }
        return "Ketan"
    }

    public var greetingName: String {
        let name = userDisplayName
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.isEmpty ? "Ketan" : first
    }

    public init(
        referenceDate: Date = Date(),
        startInDemoMode: Bool = true,
        persistToDisk: Bool = true,
        databaseURL: URL? = nil,
        authService: (any DaylightAuthenticationServiceProtocol)? = nil
    ) {
        self.referenceDate = referenceDate
        self.usesLiveClock = persistToDisk && (databaseURL == nil)
        self.persistToDisk = persistToDisk

        let dbInstance = try? SQLitePersistenceDatabase(databaseURL: databaseURL, inMemory: !persistToDisk)
        self.sqliteDatabase = dbInstance
        self.authService = authService ?? DaylightAuthenticationService(useInMemoryMock: !persistToDisk)

        let savedMode: Bool
        if persistToDisk, let storedMode = dbInstance?.getMetadata(key: "active_workspace_mode") {
            savedMode = (storedMode == "demo")
        } else {
            savedMode = startInDemoMode
        }
        self.isDemoMode = savedMode

        let initialDemo = Self.makeSyntheticAustralianDemoWorkspace(referenceDate: referenceDate)
        let initialPersonal = Self.makeBlankPersonalWorkspace(referenceDate: referenceDate)

        let resolvedDemo: TenantWorkspaceSnapshot
        if persistToDisk, let sqlDemo = try? dbInstance?.loadTenantSnapshot(tenantId: Self.demoTenantId) {
            resolvedDemo = sqlDemo
        } else if persistToDisk, let legacyDemo = Self.loadWorkspaceFromDisk(tenantId: Self.demoTenantId) {
            resolvedDemo = legacyDemo
            try? dbInstance?.saveTenantSnapshot(legacyDemo)
            try? dbInstance?.setMetadata(key: "demo_seed_completed_v2", value: "true")
        } else {
            resolvedDemo = initialDemo
            if persistToDisk {
                try? dbInstance?.saveTenantSnapshot(initialDemo)
                try? dbInstance?.setMetadata(key: "demo_seed_completed_v2", value: "true")
            }
        }

        var resolvedPersonal: TenantWorkspaceSnapshot
        if persistToDisk, let sqlPersonal = try? dbInstance?.loadTenantSnapshot(tenantId: Self.personalTenantId) {
            resolvedPersonal = sqlPersonal
        } else if persistToDisk, let legacyPersonal = Self.loadWorkspaceFromDisk(tenantId: Self.personalTenantId) {
            resolvedPersonal = legacyPersonal
            try? dbInstance?.saveTenantSnapshot(legacyPersonal)
        } else {
            resolvedPersonal = initialPersonal
            if persistToDisk {
                try? dbInstance?.saveTenantSnapshot(initialPersonal)
            }
        }
        if Self.sanitizeUntouchedLegacyPlaceholderProfile(&resolvedPersonal), persistToDisk {
            try? dbInstance?.saveTenantSnapshot(resolvedPersonal)
        }

        self.demoWorkspace = resolvedDemo
        self.personalWorkspace = resolvedPersonal

        let currentWS = savedMode ? resolvedDemo : resolvedPersonal
        let activeTid = savedMode ? Self.demoTenantId : Self.personalTenantId
        let fetchedCats = (try? dbInstance?.fetchCategories(forTenant: activeTid, includeArchived: true)) ?? []
        let initialArchivedCats = Set(fetchedCats.filter(\.isArchived).compactMap { AustralianCategory(rawValue: $0.categoryCode) })

        let initialSummary = FinancialCalculationEngine.calculateDailyAllowanceSummary(
            referenceDate: referenceDate,
            profile: currentWS.profile,
            accounts: currentWS.accounts,
            transactions: currentWS.transactions,
            fixedCommitments: currentWS.fixedCommitments,
            categoryBudgets: currentWS.categoryBudgets,
            savingsGoals: currentWS.savingsGoals,
            archivedCategories: initialArchivedCats
        )
        let initialCatProgress = FinancialCalculationEngine.calculateCategoryBudgetsProgress(
            referenceDate: referenceDate,
            profile: currentWS.profile,
            transactions: currentWS.transactions,
            categoryBudgets: currentWS.categoryBudgets,
            archivedCategories: initialArchivedCats
        )
        let initialInsights = FinancialCalculationEngine.generateDeterministicInsights(
            referenceDate: referenceDate,
            profile: currentWS.profile,
            summary: initialSummary,
            transactions: currentWS.transactions,
            recurringBills: currentWS.recurringPredictions,
            categoryProgress: initialCatProgress,
            savingsGoals: currentWS.savingsGoals
        )

        self.allowanceSummary = initialSummary
        self.categoryBudgetProgress = initialCatProgress
        self.activeInsights = initialInsights
        self.workspaceCategories = fetchedCats

        let initCal = AustralianDateHelper.calendar(for: currentWS.profile.timeZoneId)
        let initY = initCal.component(.year, from: referenceDate)
        let initM = initCal.component(.month, from: referenceDate)
        self.monthlySpendingAnalytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: initY,
            month: initM,
            referenceDate: referenceDate,
            transactions: currentWS.transactions,
            categoryBudgets: currentWS.categoryBudgets,
            savingsGoals: currentWS.savingsGoals,
            timeZoneId: currentWS.profile.timeZoneId
        )
    }

    // MARK: - Derived State Refresh

    /// Cleans up untouched legacy personal workspaces that previously seeded $3,250 pay / $500 savings ($91/day monthly)
    /// before the user ever entered income, budgets, commitments, or transactions.
    @discardableResult
    public static func sanitizeUntouchedLegacyPlaceholderProfile(_ ws: inout TenantWorkspaceSnapshot) -> Bool {
        guard ws.tenantId != demoTenantId else { return false }
        guard ws.profile.typicalTakeHomePayCents == 325_000,
              ws.profile.savingsTargetPerPeriodCents == 50_000,
              ws.transactions.isEmpty,
              ws.fixedCommitments.isEmpty,
              ws.categoryBudgets.isEmpty,
              ws.savingsGoals.isEmpty,
              ws.auditEvents.isEmpty else {
            return false
        }
        ws.profile.typicalTakeHomePayCents = 0
        ws.profile.savingsTargetPerPeriodCents = 0
        ws.notifications.removeAll { $0.categoryTag == "daily_summary" }
        return true
    }

    /// Advances `referenceDate` to the current wall-clock date/time when running live, recalculates derived summaries,
    /// and synchronizes OS notifications so day rollovers and foreground activations are always accurate.
    public func syncLiveReferenceDateAndNotifications() {
        if usesLiveClock {
            referenceDate = Date()
        }
        recalculateDerivedState()
    }

    public func recalculateDerivedState() {
        if usesLiveClock {
            referenceDate = Date()
        }
        var ws = isDemoMode ? demoWorkspace : personalWorkspace
        ws.recurringPredictions = FinancialCalculationEngine.detectRecurringPayments(
            tenantId: ws.tenantId,
            transactions: ws.transactions,
            existingPredictions: ws.recurringPredictions
        )

        let archivedCats = Set(workspaceCategories.filter(\.isArchived).compactMap { AustralianCategory(rawValue: $0.categoryCode) })

        let summary = FinancialCalculationEngine.calculateDailyAllowanceSummary(
            referenceDate: referenceDate,
            profile: ws.profile,
            accounts: ws.accounts,
            transactions: ws.transactions,
            fixedCommitments: ws.fixedCommitments,
            categoryBudgets: ws.categoryBudgets,
            savingsGoals: ws.savingsGoals,
            archivedCategories: archivedCats
        )
        let catProgress = FinancialCalculationEngine.calculateCategoryBudgetsProgress(
            referenceDate: referenceDate,
            profile: ws.profile,
            transactions: ws.transactions,
            categoryBudgets: ws.categoryBudgets,
            archivedCategories: archivedCats
        )
        let insights = FinancialCalculationEngine.generateDeterministicInsights(
            referenceDate: referenceDate,
            profile: ws.profile,
            summary: summary,
            transactions: ws.transactions,
            recurringBills: ws.recurringPredictions,
            categoryProgress: catProgress,
            savingsGoals: ws.savingsGoals
        )

        // Keep any existing in-app daily summary notification for today synchronized with latest real figures
        let auCal = AustralianDateHelper.calendar(for: ws.profile.timeZoneId)
        if let todaySummaryIdx = ws.notifications.firstIndex(where: {
            $0.categoryTag == "daily_summary" && auCal.isDate($0.createdAt, inSameDayAs: referenceDate)
        }) {
            let refreshedPayload = DaylightNotificationScheduler.buildDailyEveningSummary(
                tenantId: ws.tenantId,
                referenceDate: referenceDate,
                timeZoneId: ws.profile.timeZoneId,
                summary: summary,
                preferences: ws.notificationPreferences
            )
            ws.notifications[todaySummaryIdx].title = refreshedPayload.title
            ws.notifications[todaySummaryIdx].body = refreshedPayload.body
        }

        if isDemoMode {
            demoWorkspace = ws
        } else {
            personalWorkspace = ws
        }

        self.allowanceSummary = summary
        self.categoryBudgetProgress = catProgress
        self.activeInsights = insights

        let calY = auCal.component(.year, from: referenceDate)
        let calM = auCal.component(.month, from: referenceDate)
        self.monthlySpendingAnalytics = SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: calY,
            month: calM,
            referenceDate: referenceDate,
            transactions: ws.transactions,
            categoryBudgets: ws.categoryBudgets,
            savingsGoals: ws.savingsGoals,
            timeZoneId: ws.profile.timeZoneId
        )

        if persistToDisk {
            syncOSNotificationsInBackground(workspace: ws, summary: summary)
        }
    }

    /// Calculates or returns spending analytics for a specific year and month within the active workspace.
    public func spendingAnalytics(forYear year: Int, month: Int) -> MonthlySpendingAnalytics {
        let ws = isDemoMode ? demoWorkspace : personalWorkspace
        return SpendingAnalyticsService.shared.calculateMonthlyAnalytics(
            forYear: year,
            month: month,
            referenceDate: referenceDate,
            transactions: ws.transactions,
            categoryBudgets: ws.categoryBudgets,
            savingsGoals: ws.savingsGoals,
            timeZoneId: ws.profile.timeZoneId
        )
    }

    private func syncOSNotificationsInBackground(
        workspace ws: TenantWorkspaceSnapshot,
        summary: DailyAllowanceSummary
    ) {
        let tenant = ws.tenantId
        let refDate = referenceDate
        let currentProfile = ws.profile
        let currentPrefs = ws.notificationPreferences
        let currentAccounts = ws.accounts
        let currentTransactions = ws.transactions
        let currentFixed = ws.fixedCommitments
        let currentBudgets = ws.categoryBudgets
        let demoFlag = isDemoMode
        notificationSyncTask?.cancel()
        notificationSyncTask = Task { [weak self] in
            let result = await DaylightNotificationScheduler.syncScheduledOSNotifications(
                tenantId: tenant,
                referenceDate: refDate,
                profile: currentProfile,
                summary: currentSummaryForSync(summary),
                preferences: currentPrefs,
                accounts: currentAccounts,
                transactions: currentTransactions,
                fixedCommitments: currentFixed,
                categoryBudgets: currentBudgets,
                recurringPredictions: ws.recurringPredictions,
                isDemoMode: demoFlag
            )
            guard !Task.isCancelled, let self else { return }
            if !result {
                self.statusBannerMessage = "Notification schedules could not be updated. Check notification permission in Settings."
            }
        }
    }

    private func currentSummaryForSync(_ summary: DailyAllowanceSummary) -> DailyAllowanceSummary {
        summary
    }

    // MARK: - Security & Tenant Isolation Enforcement

    public func verifyOwnership(entityTenantId: String) throws {
        guard entityTenantId == activeTenantId else {
            throw StoreAuthorizationError.crossTenantAccessDenied(
                requestedTenant: entityTenantId,
                activeTenant: activeTenantId
            )
        }
    }

    private func recordAudit(action: String, entityType: String, entityId: String, summary: String) {
        var ws = activeWorkspace
        let event = AuditEvent(
            id: UUID(),
            tenantId: activeTenantId,
            action: action,
            entityType: entityType,
            entityId: entityId,
            summary: summary,
            createdAt: Date()
        )
        ws.auditEvents.insert(event, at: 0)
        if ws.auditEvents.count > 250 {
            ws.auditEvents = Array(ws.auditEvents.prefix(250))
        }
        activeWorkspace = ws
    }

    // MARK: - Mode Switching & Demo Reset

    public func switchWorkspaceMode(toDemo: Bool) {
        isDemoMode = toDemo
        lastUndoDescription = nil
        previousTransactionsBackup = nil
        if !toDemo && !personalWorkspace.profile.onboardingCompleted {
            showingOnboardingSheet = true
        }
    }

    public func resetSyntheticDemoData() {
        demoWorkspace = Self.makeSyntheticAustralianDemoWorkspace(referenceDate: referenceDate)
        if isDemoMode {
            recalculateDerivedState()
            saveWorkspacesIfNeeded()
        }
        statusBannerMessage = "Synthetic Australian demo data has been reset to defaults."
    }

    // MARK: - Authentication & Session Lifecycle (Welcome / Register / Login / Logout)

    /// Restores an active authenticated session on app launch if valid and unexpired.
    public func restoreAuthenticatedSessionIfAvailable() async {
        authErrorMessage = nil
        if ProcessInfo.processInfo.arguments.contains("-startDemo") {
            enterSyntheticDemoWorkspace()
            return
        }
        do {
            if let session = try await authService.restoreSession(now: referenceDate) {
                try activateAuthenticatedSession(session, isNewRegistration: false)
            } else {
                authState = .signedOut
                authNavigationRoute = .welcome
            }
        } catch {
            authState = .signedOut
            authNavigationRoute = .welcome
            authErrorMessage = error.localizedDescription
        }
    }

    /// Registers a new user account, creates an isolated personal workspace with 0 synthetic transactions,
    /// seeds default categories idempotently, and routes directly to the dashboard.
    public func registerAccount(
        fullName: String,
        email: String,
        password: String,
        confirmPassword: String,
        avatarImageData: Data? = nil
    ) async throws {
        guard !isAuthSubmitting else { return }
        let validation = AuthFormValidator.validateRegistration(
            fullName: fullName,
            email: email,
            password: password,
            confirmPassword: confirmPassword
        )
        if let err = validation.firstErrorMessage {
            authErrorMessage = err
            throw DaylightAuthenticationError.invalidInput(err)
        }

        isAuthSubmitting = true
        authErrorMessage = nil
        defer { isAuthSubmitting = false }

        do {
            let session = try await authService.register(
                fullName: fullName,
                email: email,
                password: password,
                now: referenceDate
            )
            try activateAuthenticatedSession(session, isNewRegistration: true, avatarImageData: avatarImageData)
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Authenticates an existing user, verifies workspace ownership, loads their persisted records,
    /// and routes directly to the dashboard.
    public func loginAccount(
        email: String,
        password: String
    ) async throws {
        guard !isAuthSubmitting else { return }
        let validation = AuthFormValidator.validateLogin(email: email, password: password)
        if let err = validation.firstErrorMessage {
            authErrorMessage = err
            throw DaylightAuthenticationError.invalidInput(err)
        }

        isAuthSubmitting = true
        authErrorMessage = nil
        defer { isAuthSubmitting = false }

        do {
            let session = try await authService.login(
                email: email,
                password: password,
                now: referenceDate
            )
            try activateAuthenticatedSession(session, isNewRegistration: false)
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Explicitly opens the isolated Synthetic Australian Demo Workspace for evaluation.
    public func enterSyntheticDemoWorkspace() {
        clearInMemoryAccountCaches()
        activeAuthenticatedTenantId = nil
        demoWorkspace.profile.preferredName = "Alex"
        demoWorkspace.profile.email = "alex.demo@example.com.au"
        isDemoMode = true
        let demoSession = AuthenticatedSession(
            sessionId: "demo_session_au",
            userId: "demo_user_au",
            email: "alex.demo@example.com.au",
            fullName: "Alex",
            workspaceTenantId: Self.demoTenantId,
            issuedAt: referenceDate,
            expiresAt: referenceDate.addingTimeInterval(86_400 * 30),
            providerMode: authService.providerMode
        )
        authState = .authenticated(demoSession)
        if ProcessInfo.processInfo.arguments.contains("-settings") {
            selectedSection = .settings
        } else {
            selectedSection = .overview
        }
        refreshWorkspaceCategories()
        recalculateDerivedState()
    }

    /// Signs out the current user, deactivates the SQLite and Keychain session, clears all in-memory
    /// account caches, and returns to the Welcome screen.
    public func logoutAccount() async {
        let currentSession = authState.currentSession
        let previousTenant = activeTenantId
        try? sqliteDatabase?.clearActiveSessions(tenantId: previousTenant)
        await authService.logout(session: currentSession)

        clearInMemoryAccountCaches()
        activeAuthenticatedTenantId = nil
        personalWorkspace = Self.makeBlankPersonalWorkspace(referenceDate: referenceDate)
        isDemoMode = false
        authState = .signedOut
        authNavigationRoute = .welcome
        selectedSection = .overview
        if persistToDisk {
            await DaylightNotificationScheduler.clearAllScheduledOSNotifications()
        }
        refreshWorkspaceCategories()
        recalculateDerivedState()
    }

    private func activateAuthenticatedSession(
        _ session: AuthenticatedSession,
        isNewRegistration: Bool,
        avatarImageData: Data? = nil
    ) throws {
        clearInMemoryAccountCaches()
        let tenantId = session.workspaceTenantId

        // 1. Seed system categories idempotently
        try? sqliteDatabase?.seedSystemCategoriesIfNeeded()

        // 2. Load or initialize the user's isolated personal workspace (never copying synthetic demo transactions)
        let cleanSessionName = session.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let loadedOrCreatedWorkspace: TenantWorkspaceSnapshot
        if !isNewRegistration,
           let existing = try? sqliteDatabase?.loadTenantSnapshot(tenantId: tenantId) {
            var ws = existing
            ws.tenantId = tenantId
            ws.profile.tenantId = tenantId
            _ = Self.sanitizeUntouchedLegacyPlaceholderProfile(&ws)
            if !cleanSessionName.isEmpty {
                ws.profile.preferredName = cleanSessionName
            }
            if !session.email.isEmpty {
                ws.profile.email = session.email
            }
            if let avatarImageData {
                ws.profile.avatarImageData = avatarImageData
            }
            loadedOrCreatedWorkspace = ws
        } else {
            var freshWorkspace = Self.makeBlankPersonalWorkspace(
                referenceDate: referenceDate,
                tenantId: tenantId,
                preferredName: cleanSessionName,
                email: session.email,
                onboardingCompleted: true,
                includeDefaultEverydayAccount: true
            )
            if let avatarImageData {
                freshWorkspace.profile.avatarImageData = avatarImageData
            }
            try? sqliteDatabase?.saveTenantSnapshot(freshWorkspace)
            loadedOrCreatedWorkspace = freshWorkspace
        }

        // Also keep demo workspace profile name aligned with the signed-in user if they toggle Demo Mode
        if !cleanSessionName.isEmpty {
            demoWorkspace.profile.preferredName = cleanSessionName
            demoWorkspace.profile.email = session.email
        }

        // 3. Verify workspace ownership in SQLite (`workspace_memberships`)
        try? sqliteDatabase?.saveTenantSnapshot(loadedOrCreatedWorkspace)
        if let db = sqliteDatabase {
            let profileUserUUID = loadedOrCreatedWorkspace.profile.id
            let ownsWorkspace = db.verifyWorkspaceOwnership(tenantId: tenantId, userId: profileUserUUID)
            if !ownsWorkspace {
                throw DaylightAuthenticationError.unauthorizedWorkspaceAccess
            }
            // 4. Record non-secret session metadata in SQLite `app_sessions`
            try? db.upsertAppSession(
                AppSessionRecord(
                    sessionId: session.sessionId,
                    userId: profileUserUUID.uuidString,
                    tenantId: tenantId,
                    authProvider: session.providerMode.rawValue,
                    createdAt: session.issuedAt,
                    lastActiveAt: referenceDate,
                    isActive: true
                )
            )
            if persistToDisk {
                try? db.setMetadata(key: "active_workspace_mode", value: "personal")
            }
        }

        // 5. Switch active workspace to the signed-in user's personal workspace
        activeAuthenticatedTenantId = tenantId
        personalWorkspace = loadedOrCreatedWorkspace
        isDemoMode = false
        authState = .authenticated(session)
        if ProcessInfo.processInfo.arguments.contains("-settings") {
            selectedSection = .settings
        } else {
            selectedSection = .overview
        }
        refreshWorkspaceCategories()
        recalculateDerivedState()
    }

    private func clearInMemoryAccountCaches() {
        lastUndoDescription = nil
        previousTransactionsBackup = nil
        previousAccountsBackup = nil
        transactionCategoryDrilldown = nil
        customCategoryFilterId = nil
        statusBannerMessage = nil
        authErrorMessage = nil
    }

    // MARK: - Onboarding & Profile Operations

    public func completeOnboarding(
        preferredName: String,
        timeZoneId: String,
        employmentType: EmploymentIncomeType,
        payFrequency: PayFrequency,
        takeHomePayCents: MoneyCents,
        nextPayDate: Date,
        fixedExpensesCents: MoneyCents,
        savingsTargetCents: MoneyCents,
        budgetingMethod: BudgetingMethod
    ) {
        var ws = activeWorkspace
        let fallbackName = authState.currentSession?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (fallbackName.isEmpty ? "Friend" : fallbackName)
            : preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        ws.profile.preferredName = resolvedName
        syncAuthenticatedSessionFullNameIfNeeded(resolvedName)
        ws.profile.timeZoneId = timeZoneId
        ws.profile.employmentType = employmentType
        ws.profile.payFrequency = payFrequency
        ws.profile.typicalTakeHomePayCents = max(0, takeHomePayCents)
        ws.profile.nextPayDate = nextPayDate
        ws.profile.savingsTargetPerPeriodCents = max(0, savingsTargetCents)
        ws.profile.preferredBudgetingMethod = budgetingMethod
        ws.profile.onboardingCompleted = true
        ws.profile.updatedAt = Date()

        if fixedExpensesCents > 0 && ws.fixedCommitments.isEmpty {
            ws.fixedCommitments.append(
                FixedCommitment(
                    id: UUID(),
                    tenantId: activeTenantId,
                    title: "Core Housing & Fixed Bills",
                    category: .rentAndMortgage,
                    amountCents: fixedExpensesCents,
                    frequency: payFrequency,
                    nextDueDate: nextPayDate,
                    isConfirmed: true
                )
            )
        }

        if ws.accounts.isEmpty {
            ws.accounts.append(
                FinancialAccount(
                    id: UUID(),
                    tenantId: activeTenantId,
                    institutionName: "Everyday Bank Account (Manual)",
                    nickname: "Everyday Spending",
                    accountType: .everydayTransaction,
                    maskedAccountNumber: "•••• 1001",
                    currencyCode: "AUD",
                    availableBalanceCents: 0,
                    currentBalanceCents: 0,
                    balanceUpdatedAt: Date(),
                    connectionStatus: .manual,
                    lastSuccessfulSyncAt: Date(),
                    lastSyncErrorMessage: nil,
                    dataCoverageDescription: "Manual balance & CSV statements",
                    consentRecordId: nil,
                    includeInSafeToSpendCash: true
                )
            )
        }

        activeWorkspace = ws
        recordAudit(
            action: "ONBOARDING_COMPLETED",
            entityType: "UserProfile",
            entityId: ws.profile.id.uuidString,
            summary: "Configured \(payFrequency.displayName) budget with \(AustralianMoneyFormatter.format(cents: takeHomePayCents)) take-home pay."
        )
        showingOnboardingSheet = false
    }

    public func updateProfile(_ updated: UserProfile) throws {
        try verifyOwnership(entityTenantId: updated.tenantId)
        var ws = activeWorkspace
        var copy = updated
        let cleanName = copy.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty {
            copy.preferredName = cleanName
            syncAuthenticatedSessionFullNameIfNeeded(cleanName)
            personalWorkspace.profile.preferredName = cleanName
            demoWorkspace.profile.preferredName = cleanName
        }
        copy.updatedAt = Date()
        ws.profile = copy
        activeWorkspace = ws
        recordAudit(
            action: "PROFILE_UPDATED",
            entityType: "UserProfile",
            entityId: copy.id.uuidString,
            summary: "Updated preferences (Method: \(copy.preferredBudgetingMethod.displayName), Timezone: \(copy.timeZoneId))."
        )
    }

    /// Switches the profile pay frequency while preserving the user's annual income and savings.
    /// Take-home pay and per-period savings are rescaled using annualised equivalence
    /// (52 weeks = 26 fortnights = 12 months = 13 four-week cycles), integer cents, half-up rounding.
    /// Example: $3,250.00 fortnightly → $7,041.67 monthly (3,250 × 26 ÷ 12).
    public func changePayFrequency(to newFrequency: PayFrequency) throws {
        let oldFrequency = profile.payFrequency
        guard newFrequency != oldFrequency else { return }
        var p = profile
        p.tenantId = activeTenantId
        p.typicalTakeHomePayCents = FinancialCalculationEngine.normalizedAmountForCalculation(
            amountCents: max(0, p.typicalTakeHomePayCents),
            from: oldFrequency,
            to: newFrequency
        )
        p.savingsTargetPerPeriodCents = FinancialCalculationEngine.normalizedAmountForCalculation(
            amountCents: max(0, p.savingsTargetPerPeriodCents),
            from: oldFrequency,
            to: newFrequency
        )
        p.payFrequency = newFrequency
        try updateProfile(p)
    }

    /// Updates the user's profile avatar picture (or removes it if nil) and persists it in SQLite and active workspace.
    public func updateProfileAvatar(imageData: Data?) throws {
        var p = profile
        p.tenantId = activeTenantId
        p.avatarImageData = imageData
        p.updatedAt = Date()
        try updateProfile(p)
        recordAudit(
            action: imageData == nil ? "PROFILE_AVATAR_REMOVED" : "PROFILE_AVATAR_UPDATED",
            entityType: "UserProfile",
            entityId: p.id.uuidString,
            summary: imageData == nil ? "Removed custom profile avatar." : "Updated profile avatar (\(imageData?.count ?? 0) bytes)."
        )
    }

    private func syncAuthenticatedSessionFullNameIfNeeded(_ newFullName: String) {
        let cleanName = newFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let existingSession = authState.currentSession else { return }
        authService.updateAuthenticatedUserName(cleanName)
        let updatedSession = AuthenticatedSession(
            sessionId: existingSession.sessionId,
            userId: existingSession.userId,
            email: existingSession.email,
            fullName: cleanName,
            workspaceTenantId: existingSession.workspaceTenantId,
            issuedAt: existingSession.issuedAt,
            expiresAt: existingSession.expiresAt,
            providerMode: existingSession.providerMode
        )
        authState = .authenticated(updatedSession)
    }

    // MARK: - Transaction Management (Add, Edit, Delete, Split, Bulk Categorise, Undo)

    public func addManualTransaction(
        accountId: UUID,
        merchantName: String,
        rawDescription: String,
        amountCents: MoneyCents,
        direction: TransactionDirection,
        category: AustralianCategory,
        kind: TransactionKind,
        occurredAt: Date,
        userNote: String,
        excludeFromBudget: Bool,
        linkedFixedCommitmentId: UUID? = nil,
        idempotencyKey: String? = nil
    ) throws {
        var ws = activeWorkspace
        if let key = idempotencyKey {
            if ws.processedIdempotencyKeys.contains(key) {
                throw StoreAuthorizationError.duplicateIdempotencyKey(key)
            }
            ws.processedIdempotencyKeys.append(key)
        }

        // Ensure an account exists in the workspace if a new user hasn't created one yet
        let resolvedAccountId: UUID
        if ws.accounts.contains(where: { $0.id == accountId }) {
            resolvedAccountId = accountId
        } else if let existingFirst = ws.accounts.first?.id {
            resolvedAccountId = existingFirst
        } else {
            let defaultAccount = FinancialAccount(
                id: accountId,
                tenantId: activeTenantId,
                institutionName: "Australian Bank Account (Manual)",
                nickname: "Everyday Spending",
                accountType: .everydayTransaction,
                maskedAccountNumber: "•••• 1001",
                currencyCode: "AUD",
                availableBalanceCents: 0,
                currentBalanceCents: 0,
                balanceUpdatedAt: occurredAt,
                connectionStatus: .manual,
                lastSuccessfulSyncAt: occurredAt,
                lastSyncErrorMessage: nil,
                dataCoverageDescription: "Manual entries & CSV statements",
                consentRecordId: nil,
                includeInSafeToSpendCash: true
            )
            ws.accounts.append(defaultAccount)
            resolvedAccountId = defaultAccount.id
        }

        let fp = FinancialCalculationEngine.makeReconciliationFingerprint(
            accountId: resolvedAccountId,
            date: occurredAt,
            amountCents: abs(amountCents),
            direction: direction,
            rawDescription: rawDescription.isEmpty ? merchantName : rawDescription,
            sourceTransactionId: idempotencyKey
        )

        let newTx = TransactionRecord(
            id: UUID(),
            tenantId: activeTenantId,
            accountId: resolvedAccountId,
            sourceTransactionId: idempotencyKey,
            reconciliationFingerprint: fp,
            merchantName: merchantName.trimmingCharacters(in: .whitespacesAndNewlines),
            rawDescription: rawDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? merchantName : rawDescription,
            occurredAt: occurredAt,
            amountCents: abs(amountCents),
            direction: direction,
            category: category,
            classificationConfidence: 1.0,
            status: .posted,
            kind: kind,
            isRecurring: category.isDefaultFixedCommitment,
            paymentRail: "Manual Entry",
            source: .manualEntry,
            userNote: userNote,
            excludeFromBudget: excludeFromBudget,
            linkedOriginalTransactionId: nil,
            linkedFixedCommitmentId: linkedFixedCommitmentId,
            splits: [],
            calculationVersion: FinancialCalculationEngine.currentCalculationVersion,
            updatedAt: Date()
        )

        ws.transactions.insert(newTx, at: 0)
        // Adjust manual account balance
        if let idx = ws.accounts.firstIndex(where: { $0.id == resolvedAccountId }) {
            let delta = (direction == .debit) ? -abs(amountCents) : abs(amountCents)
            ws.accounts[idx].availableBalanceCents += delta
            ws.accounts[idx].currentBalanceCents += delta
            ws.accounts[idx].balanceUpdatedAt = Date()
        }

        activeWorkspace = ws
        recordAudit(
            action: "TRANSACTION_ADDED",
            entityType: "TransactionRecord",
            entityId: newTx.id.uuidString,
            summary: "Added \(merchantName) (\(AustralianMoneyFormatter.format(cents: abs(amountCents)))) in \(category.displayName)."
        )
    }

    public func updateTransaction(
        _ updated: TransactionRecord,
        createMerchantRuleForFuture: Bool = false,
        applyCategoryToUnconfirmed: Bool = false
    ) throws {
        try verifyOwnership(entityTenantId: updated.tenantId)
        guard FinancialCalculationEngine.isValidDirection(updated.direction, for: updated.kind) else {
            throw StoreAuthorizationError.invalidTransactionDirection(kind: updated.kind, direction: updated.direction)
        }
        if !updated.splits.isEmpty {
            let splitSum = updated.splits.reduce(MoneyCents(0)) { $0 + $1.amountCents }
            if splitSum != updated.amountCents {
                throw StoreAuthorizationError.invalidSplitTotal(expectedCents: updated.amountCents, actualCents: splitSum)
            }
        }

        var ws = activeWorkspace
        guard let idx = ws.transactions.firstIndex(where: { $0.id == updated.id }) else { return }
        let oldTx = ws.transactions[idx]

        previousTransactionsBackup = ws.transactions
        previousAccountsBackup = ws.accounts
        lastUndoDescription = "Updated \(updated.merchantName)"

        // Adjust account balances if amount, direction, or account changed
        let oldSigned = oldTx.direction == .debit ? -abs(oldTx.amountCents) : abs(oldTx.amountCents)
        let newSigned = updated.direction == .debit ? -abs(updated.amountCents) : abs(updated.amountCents)
        if oldTx.accountId == updated.accountId {
            let diff = newSigned - oldSigned
            if diff != 0, let acctIdx = ws.accounts.firstIndex(where: { $0.id == updated.accountId }) {
                ws.accounts[acctIdx].availableBalanceCents += diff
                ws.accounts[acctIdx].currentBalanceCents += diff
                ws.accounts[acctIdx].balanceUpdatedAt = Date()
            }
        } else {
            if let oldAcctIdx = ws.accounts.firstIndex(where: { $0.id == oldTx.accountId }) {
                ws.accounts[oldAcctIdx].availableBalanceCents -= oldSigned
                ws.accounts[oldAcctIdx].currentBalanceCents -= oldSigned
                ws.accounts[oldAcctIdx].balanceUpdatedAt = Date()
            }
            if let newAcctIdx = ws.accounts.firstIndex(where: { $0.id == updated.accountId }) {
                ws.accounts[newAcctIdx].availableBalanceCents += newSigned
                ws.accounts[newAcctIdx].currentBalanceCents += newSigned
                ws.accounts[newAcctIdx].balanceUpdatedAt = Date()
            }
        }

        var copy = updated
        copy.amountCents = abs(updated.amountCents)
        copy.classificationConfidence = 1.0
        copy.updatedAt = Date()
        ws.transactions[idx] = copy

        if createMerchantRuleForFuture {
            let optimalSubstring = ClassificationFeedbackService.shared.deriveOptimalMatchSubstring(
                rawDescription: copy.rawDescription,
                merchantName: copy.merchantName
            )
            let (rule, updatedRules) = ClassificationFeedbackService.shared.createOrUpdateRule(
                tenantId: activeTenantId,
                matchSubstring: optimalSubstring,
                normalizedMerchantName: copy.merchantName,
                assignedCategory: copy.category,
                applyToFutureOnly: false,
                existingRules: ws.merchantRules
            )
            ws.merchantRules = updatedRules
            if applyCategoryToUnconfirmed, copy.category != oldTx.category {
                let (updatedTransactions, _) = ClassificationFeedbackService.shared.applyLearnedRuleToUnconfirmedTransactions(
                    rule: rule,
                    transactions: ws.transactions
                )
                ws.transactions = updatedTransactions
            }
        }

        activeWorkspace = ws
        recordAudit(
            action: "TRANSACTION_UPDATED",
            entityType: "TransactionRecord",
            entityId: copy.id.uuidString,
            summary: "Edited \(copy.merchantName) -> Category: \(copy.category.displayName), Kind: \(copy.kind.displayName)."
        )
    }

    /// User category correction with automatic rule learning and optional propagation to matching unconfirmed transactions.
    public func correctTransactionCategory(
        transactionId: UUID,
        newCategory: AustralianCategory,
        createRule: Bool = true,
        applyToUnconfirmed: Bool = false
    ) throws {
        var ws = activeWorkspace
        guard let idx = ws.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        var tx = ws.transactions[idx]
        try verifyOwnership(entityTenantId: tx.tenantId)

        tx.category = newCategory
        tx.classificationConfidence = 1.0
        tx.updatedAt = Date()
        ws.transactions[idx] = tx

        if createRule {
            let optimalSubstring = ClassificationFeedbackService.shared.deriveOptimalMatchSubstring(
                rawDescription: tx.rawDescription,
                merchantName: tx.merchantName
            )
            let (rule, updatedRules) = ClassificationFeedbackService.shared.createOrUpdateRule(
                tenantId: activeTenantId,
                matchSubstring: optimalSubstring,
                normalizedMerchantName: tx.merchantName,
                assignedCategory: newCategory,
                applyToFutureOnly: !applyToUnconfirmed,
                existingRules: ws.merchantRules
            )
            ws.merchantRules = updatedRules

            if applyToUnconfirmed {
                let (updatedTxs, _) = ClassificationFeedbackService.shared.applyLearnedRuleToUnconfirmedTransactions(
                    rule: rule,
                    transactions: ws.transactions
                )
                ws.transactions = updatedTxs
            }
        }

        activeWorkspace = ws
        recordAudit(
            action: "CATEGORY_CORRECTED",
            entityType: "TransactionRecord",
            entityId: tx.id.uuidString,
            summary: "Corrected category for \(tx.merchantName) to \(newCategory.displayName)."
        )
    }

    public func deleteTransaction(id: UUID) throws {
        var ws = activeWorkspace
        guard let idx = ws.transactions.firstIndex(where: { $0.id == id }) else { return }
        let removed = ws.transactions[idx]
        try verifyOwnership(entityTenantId: removed.tenantId)

        previousTransactionsBackup = ws.transactions
        previousAccountsBackup = ws.accounts
        lastUndoDescription = "Deleted \(removed.merchantName)"

        // Reverse manual balance effect
        if let acctIdx = ws.accounts.firstIndex(where: { $0.id == removed.accountId }) {
            let reversal = removed.direction == .debit ? abs(removed.amountCents) : -abs(removed.amountCents)
            ws.accounts[acctIdx].availableBalanceCents += reversal
            ws.accounts[acctIdx].currentBalanceCents += reversal
            ws.accounts[acctIdx].balanceUpdatedAt = Date()
        }

        ws.transactions.remove(at: idx)
        activeWorkspace = ws
        statusBannerMessage = "Deleted transaction '\(removed.merchantName)'."
        recordAudit(
            action: "TRANSACTION_DELETED",
            entityType: "TransactionRecord",
            entityId: removed.id.uuidString,
            summary: "Deleted transaction '\(removed.merchantName)' (\(AustralianMoneyFormatter.format(cents: removed.amountCents)))."
        )
    }

    public func bulkCategoriseTransactions(
        ids: Set<UUID>,
        newCategory: AustralianCategory
    ) {
        guard !ids.isEmpty else { return }
        var ws = activeWorkspace
        previousTransactionsBackup = ws.transactions
        previousAccountsBackup = ws.accounts
        lastUndoDescription = "Bulk categorised \(ids.count) transaction\(ids.count == 1 ? "" : "s") to \(newCategory.displayName)"

        for i in ws.transactions.indices where ids.contains(ws.transactions[i].id) {
            ws.transactions[i].category = newCategory
            ws.transactions[i].classificationConfidence = 1.0
            ws.transactions[i].updatedAt = Date()
        }
        activeWorkspace = ws
        recordAudit(
            action: "BULK_CATEGORISE",
            entityType: "TransactionRecord",
            entityId: "count:\(ids.count)",
            summary: "Assigned \(ids.count) transactions to \(newCategory.displayName)."
        )
    }

    public func undoLastTransactionChange() {
        guard let backup = previousTransactionsBackup else { return }
        var ws = activeWorkspace
        ws.transactions = backup
        if let acctBackup = previousAccountsBackup {
            ws.accounts = acctBackup
        }
        previousTransactionsBackup = nil
        previousAccountsBackup = nil
        let msg = lastUndoDescription ?? "Change"
        lastUndoDescription = nil
        activeWorkspace = ws
        statusBannerMessage = "Undid: \(msg)"
    }

    // MARK: - Statement CSV Import Workflow

    public func commitCSVStatementImport(
        fileName: String,
        targetAccountId: UUID,
        previewRows: [ParsedCSVRowPreview],
        idempotencyKey: String
    ) throws -> ImportJobRecord {
        var ws = activeWorkspace
        if ws.processedIdempotencyKeys.contains(idempotencyKey) {
            throw StoreAuthorizationError.duplicateIdempotencyKey(idempotencyKey)
        }

        let existingFPs = Set(ws.transactions.map(\.reconciliationFingerprint))
        var importedCount = 0
        var duplicateCount = 0
        var rejectedCount = 0

        var importedNetBalanceDeltaCents: MoneyCents = 0

        for row in previewRows {
            if row.validationError != nil {
                rejectedCount += 1
                continue
            }
            if row.isDuplicate || existingFPs.contains(row.fingerprint) {
                duplicateCount += 1
                continue
            }
            guard let date = row.parsedDate, let cents = row.parsedAmountCents else {
                rejectedCount += 1
                continue
            }

            let isCreditCard = ws.accounts.first(where: { $0.id == targetAccountId })?.accountType == .creditCard
            let intelligentClassification = IntelligentCategorisationEngine.shared.classify(
                rawDescription: row.parsedDescription,
                amountCents: cents,
                direction: row.parsedDirection,
                isCreditCardAccount: isCreditCard,
                userMerchantRules: ws.merchantRules,
                historicalTransactions: ws.transactions
            )

            let tx = TransactionRecord(
                id: UUID(),
                tenantId: activeTenantId,
                accountId: targetAccountId,
                sourceTransactionId: nil,
                reconciliationFingerprint: row.fingerprint,
                merchantName: intelligentClassification.normalizedMerchant,
                rawDescription: row.parsedDescription,
                occurredAt: date,
                amountCents: cents,
                direction: row.parsedDirection,
                category: intelligentClassification.category,
                classificationConfidence: intelligentClassification.confidence,
                status: .posted,
                kind: intelligentClassification.kind,
                isRecurring: intelligentClassification.category.isDefaultFixedCommitment,
                paymentRail: intelligentClassification.paymentRail ?? "Statement Import",
                source: .csvStatementImport,
                userNote: "Imported from \(fileName)",
                excludeFromBudget: intelligentClassification.kind == .ownAccountTransfer || intelligentClassification.kind == .creditCardRepayment,
                linkedOriginalTransactionId: nil,
                splits: [],
                calculationVersion: FinancialCalculationEngine.currentCalculationVersion,
                updatedAt: Date()
            )
            ws.transactions.append(tx)
            importedCount += 1
            importedNetBalanceDeltaCents += (row.parsedDirection == .debit ? -abs(cents) : abs(cents))
        }

        if importedCount > 0,
           let acctIdx = ws.accounts.firstIndex(where: { $0.id == targetAccountId && $0.connectionStatus == .manual }) {
            ws.accounts[acctIdx].availableBalanceCents += importedNetBalanceDeltaCents
            ws.accounts[acctIdx].currentBalanceCents += importedNetBalanceDeltaCents
            ws.accounts[acctIdx].balanceUpdatedAt = Date()
        }

        let job = ImportJobRecord(
            id: UUID(),
            tenantId: activeTenantId,
            fileName: fileName,
            targetAccountId: targetAccountId,
            idempotencyKey: idempotencyKey,
            totalRows: previewRows.count,
            importedCount: importedCount,
            duplicateSkippedCount: duplicateCount,
            rejectedCount: rejectedCount,
            status: rejectedCount == 0 ? "completed" : "completed_with_warnings",
            createdAt: Date()
        )
        ws.importJobs.insert(job, at: 0)
        ws.processedIdempotencyKeys.append(idempotencyKey)
        activeWorkspace = ws

        // Persist rejected rows to `import_job_issues` so they remain inspectable and repairable across restarts
        let issues: [ImportJobIssueRecord] = previewRows.compactMap { row in
            guard let err = row.validationError else { return nil }
            return ImportJobIssueRecord(
                id: row.id,
                importJobId: job.id,
                tenantId: activeTenantId,
                rowNumber: row.rowNumber,
                sanitizedRawLine: FinancialCalculationEngine.sanitizeCSVCell(row.rawLine),
                validationError: err,
                isRepaired: false,
                repairedTransactionId: nil,
                createdAt: job.createdAt
            )
        }
        if !issues.isEmpty {
            try? sqliteDatabase?.saveImportJobIssues(issues)
        }

        recordAudit(
            action: "STATEMENT_IMPORTED",
            entityType: "ImportJobRecord",
            entityId: job.id.uuidString,
            summary: "Imported \(importedCount) transactions from '\(fileName)' (\(duplicateCount) duplicates skipped, \(rejectedCount) rejected)."
        )
        return job
    }

    public func fetchPersistedImportIssues(importJobId: UUID? = nil) -> [ImportJobIssueRecord] {
        (try? sqliteDatabase?.fetchImportJobIssues(tenantId: activeTenantId, importJobId: importJobId)) ?? []
    }

    // MARK: - Custom Categories (System + Workspace-Scoped CRUD)

    public func refreshWorkspaceCategories(includeArchived: Bool = true) {
        workspaceCategories = (try? sqliteDatabase?.fetchCategories(forTenant: activeTenantId, includeArchived: includeArchived)) ?? []
    }

    public func fetchWorkspaceCategories(includeArchived: Bool = false) -> [TransactionCategoryRecord] {
        (try? sqliteDatabase?.fetchCategories(forTenant: activeTenantId, includeArchived: includeArchived)) ?? []
    }

    public func customCategories(includeArchived: Bool = false) -> [TransactionCategoryRecord] {
        workspaceCategories.filter { !$0.isSystem && (includeArchived || !$0.isArchived) }
    }

    public func createCustomCategory(
        name: String,
        iconName: String = "tag.fill",
        categoryType: TransactionCategoryType = .expense,
        displayOrder: Int = 190
    ) throws -> TransactionCategoryRecord {
        guard let db = sqliteDatabase else {
            throw SQLitePersistenceDatabase.DatabaseError.openFailed("SQLite database unavailable")
        }
        let created = try db.createCustomCategory(
            tenantId: activeTenantId,
            name: name,
            iconName: iconName,
            categoryType: categoryType,
            displayOrder: displayOrder
        )
        refreshWorkspaceCategories()
        recordAudit(
            action: "CUSTOM_CATEGORY_CREATED",
            entityType: "TransactionCategory",
            entityId: created.id,
            summary: "Created custom category '\(created.name)' (\(created.categoryType.rawValue))."
        )
        return created
    }

    public func updateCustomCategory(_ updated: TransactionCategoryRecord) throws {
        guard let db = sqliteDatabase else { return }
        try db.updateCustomCategory(
            categoryId: updated.id,
            tenantId: activeTenantId,
            newName: updated.name,
            newDisplayOrder: updated.displayOrder,
            isArchived: updated.isArchived
        )
        refreshWorkspaceCategories()
        recalculateDerivedState()
        recordAudit(
            action: "CUSTOM_CATEGORY_UPDATED",
            entityType: "TransactionCategory",
            entityId: updated.id,
            summary: "Updated custom category '\(updated.name)' (archived: \(updated.isArchived))."
        )
    }

    public func archiveCategory(_ category: AustralianCategory) {
        if let idx = workspaceCategories.firstIndex(where: { $0.categoryCode == category.rawValue }) {
            workspaceCategories[idx].isArchived = true
            try? sqliteDatabase?.updateCustomCategory(
                categoryId: workspaceCategories[idx].id,
                tenantId: activeTenantId,
                isArchived: true
            )
        } else {
            let record = TransactionCategoryRecord(
                id: "system:\(category.rawValue)",
                tenantId: activeTenantId,
                categoryCode: category.rawValue,
                name: category.displayName,
                iconName: category.symbolName,
                displayOrder: 999,
                categoryType: .expense,
                isSystemDefault: true,
                isCustom: false,
                isArchived: true
            )
            workspaceCategories.append(record)
        }
        recalculateDerivedState()
    }

    public func moveCustomCategory(categoryId: String, direction: Int) throws {
        var customList = workspaceCategories
            .filter { !$0.isSystemDefault }
            .sorted {
                if $0.displayOrder == $1.displayOrder {
                    return $0.name < $1.name
                }
                return $0.displayOrder < $1.displayOrder
            }
        guard let idx = customList.firstIndex(where: { $0.id == categoryId }) else { return }
        let targetIdx = idx + direction
        guard targetIdx >= 0 && targetIdx < customList.count else { return }
        customList.swapAt(idx, targetIdx)
        for (offset, item) in customList.enumerated() {
            let newOrder = 150 + (offset * 5)
            try? sqliteDatabase?.updateCustomCategory(
                categoryId: item.id,
                tenantId: activeTenantId,
                newName: item.name,
                newDisplayOrder: newOrder,
                isArchived: item.isArchived
            )
        }
        refreshWorkspaceCategories()
    }

    public func deleteCustomCategory(
        categoryId: String,
        reassignToCategory: AustralianCategory? = nil
    ) throws {
        guard let db = sqliteDatabase else { return }
        try db.deleteCustomCategory(
            categoryId: categoryId,
            tenantId: activeTenantId,
            reassignToCategory: reassignToCategory
        )
        if let sqlSnapshot = try? db.loadTenantSnapshot(tenantId: activeTenantId) {
            if isDemoMode {
                demoWorkspace = sqlSnapshot
            } else {
                personalWorkspace = sqlSnapshot
            }
            recalculateDerivedState()
        }
        refreshWorkspaceCategories()
        recordAudit(
            action: "CUSTOM_CATEGORY_DELETED",
            entityType: "TransactionCategory",
            entityId: categoryId,
            summary: "Deleted custom category \(categoryId)."
        )
    }

    // MARK: - Budgets & Fixed Commitments Operations

    public func upsertCategoryBudget(
        category: AustralianCategory,
        limitCents: MoneyCents,
        rolloverEnabled: Bool,
        periodType: PayFrequency? = nil,
        linkedFixedCommitmentId: UUID? = nil
    ) {
        var ws = activeWorkspace
        let defaultActivePeriodType: PayFrequency = (ws.profile.preferredBudgetingMethod == .monthlyFlexible)
            ? .monthly
            : ws.profile.payFrequency
        let sanitizedLimit = max(0, limitCents)
        let resolvedPeriodType: PayFrequency

        if let idx = ws.categoryBudgets.firstIndex(where: { $0.category == category }) {
            let keptPeriod = periodType ?? ws.categoryBudgets[idx].periodType
            resolvedPeriodType = keptPeriod
            ws.categoryBudgets[idx].limitCents = sanitizedLimit
            ws.categoryBudgets[idx].rolloverEnabled = rolloverEnabled
            ws.categoryBudgets[idx].periodType = keptPeriod
            if let linkedFixedCommitmentId {
                ws.categoryBudgets[idx].linkedFixedCommitmentId = linkedFixedCommitmentId
            }
            ws.categoryBudgets[idx].updatedAt = Date()
        } else {
            resolvedPeriodType = periodType ?? defaultActivePeriodType
            ws.categoryBudgets.append(
                CategoryBudget(
                    id: UUID(),
                    tenantId: activeTenantId,
                    category: category,
                    limitCents: sanitizedLimit,
                    rolloverEnabled: rolloverEnabled,
                    rolloverBalanceCents: 0,
                    periodType: resolvedPeriodType,
                    linkedFixedCommitmentId: linkedFixedCommitmentId,
                    updatedAt: Date()
                )
            )
        }
        activeWorkspace = ws
        recordAudit(
            action: "CATEGORY_BUDGET_UPSERTED",
            entityType: "CategoryBudget",
            entityId: category.rawValue,
            summary: "Set \(category.displayName) budget to \(AustralianMoneyFormatter.format(cents: sanitizedLimit)) (\(resolvedPeriodType.displayName))."
        )
    }

    public func deleteCategoryBudget(id: UUID) {
        var ws = activeWorkspace
        ws.categoryBudgets.removeAll { $0.id == id }
        activeWorkspace = ws
    }

    public func addFixedCommitment(
        title: String,
        category: AustralianCategory,
        amountCents: MoneyCents,
        frequency: PayFrequency,
        nextDueDate: Date
    ) {
        var ws = activeWorkspace
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let sanitizedAmount = max(0, amountCents)
        ws.fixedCommitments.append(
            FixedCommitment(
                id: UUID(),
                tenantId: activeTenantId,
                title: trimmedTitle,
                category: category,
                amountCents: sanitizedAmount,
                frequency: frequency,
                nextDueDate: nextDueDate,
                isConfirmed: true
            )
        )
        activeWorkspace = ws
        recordAudit(
            action: "FIXED_COMMITMENT_ADDED",
            entityType: "FixedCommitment",
            entityId: trimmedTitle,
            summary: "Added fixed commitment '\(trimmedTitle)' (\(AustralianMoneyFormatter.format(cents: sanitizedAmount)) \(frequency.displayName))."
        )
    }

    public func updateFixedCommitment(
        id: UUID,
        title: String,
        category: AustralianCategory,
        amountCents: MoneyCents,
        frequency: PayFrequency,
        nextDueDate: Date
    ) {
        var ws = activeWorkspace
        guard let idx = ws.fixedCommitments.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let sanitizedAmount = max(0, amountCents)
        ws.fixedCommitments[idx].title = trimmedTitle
        ws.fixedCommitments[idx].category = category
        ws.fixedCommitments[idx].amountCents = sanitizedAmount
        ws.fixedCommitments[idx].frequency = frequency
        ws.fixedCommitments[idx].nextDueDate = nextDueDate
        activeWorkspace = ws
        recordAudit(
            action: "FIXED_COMMITMENT_UPDATED",
            entityType: "FixedCommitment",
            entityId: id.uuidString,
            summary: "Updated fixed commitment '\(trimmedTitle)' (\(AustralianMoneyFormatter.format(cents: sanitizedAmount)) \(frequency.displayName))."
        )
    }

    public func deleteFixedCommitment(id: UUID) {
        var ws = activeWorkspace
        ws.fixedCommitments.removeAll { $0.id == id }
        activeWorkspace = ws
    }

    // MARK: - Recurring Payment Predictions (Confirm / Edit / Dismiss)

    public func confirmRecurringPrediction(id: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.recurringPredictions.firstIndex(where: { $0.id == id }) else { return }
        ws.recurringPredictions[idx].isConfirmedByUser = true
        ws.recurringPredictions[idx].confidence = .confirmedSchedule
        activeWorkspace = ws
        recordAudit(
            action: "RECURRING_BILL_CONFIRMED",
            entityType: "RecurringPaymentPrediction",
            entityId: id.uuidString,
            summary: "Confirmed recurring payment schedule for \(ws.recurringPredictions[idx].merchantName)."
        )
    }

    public func dismissRecurringPrediction(id: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.recurringPredictions.firstIndex(where: { $0.id == id }) else { return }
        ws.recurringPredictions[idx].isDismissed = true
        activeWorkspace = ws
    }

    public func addConfirmedRecurringBill(
        merchantName: String,
        category: AustralianCategory,
        expectedAmountCents: MoneyCents,
        frequency: RecurringFrequency,
        nextExpectedDate: Date,
        paymentRail: String
    ) {
        var ws = activeWorkspace
        ws.recurringPredictions.append(
            RecurringPaymentPrediction(
                id: UUID(),
                tenantId: activeTenantId,
                merchantName: merchantName,
                category: category,
                expectedAmountCents: max(0, expectedAmountCents),
                frequency: frequency,
                nextExpectedDate: nextExpectedDate,
                lastPaymentDate: Date(),
                confidence: .confirmedSchedule,
                isConfirmedByUser: true,
                isDismissed: false,
                paymentRail: paymentRail,
                linkedTransactionIds: []
            )
        )
        activeWorkspace = ws
    }

    // MARK: - Savings Goals

    public func addSavingsGoal(
        name: String,
        iconName: String,
        targetAmountCents: MoneyCents,
        initialSavedCents: MoneyCents,
        targetDate: Date?,
        linkedAccountId: UUID?
    ) {
        var ws = activeWorkspace
        let goal = SavingsGoal(
            id: UUID(),
            tenantId: activeTenantId,
            name: name,
            iconName: iconName,
            targetAmountCents: max(100, targetAmountCents),
            currentSavedCents: max(0, initialSavedCents),
            targetDate: targetDate,
            linkedAccountId: linkedAccountId,
            contributions: initialSavedCents > 0 ? [
                SavingsContribution(id: UUID(), date: Date(), amountCents: initialSavedCents, note: "Opening balance")
            ] : [],
            assumptionsNote: "Progress reflects contributions only, excluding unrecorded returns and compounding.",
            createdAt: Date()
        )
        ws.savingsGoals.append(goal)
        activeWorkspace = ws
        recordAudit(
            action: "SAVINGS_GOAL_CREATED",
            entityType: "SavingsGoal",
            entityId: goal.id.uuidString,
            summary: "Created savings goal '\(name)' with target \(AustralianMoneyFormatter.format(cents: targetAmountCents))."
        )
    }

    public func updateSavingsGoal(
        goalId: UUID,
        name: String,
        iconName: String,
        targetAmountCents: MoneyCents,
        targetDate: Date?
    ) {
        var ws = activeWorkspace
        guard let idx = ws.savingsGoals.firstIndex(where: { $0.id == goalId }) else { return }
        ws.savingsGoals[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ws.savingsGoals[idx].iconName = iconName
        ws.savingsGoals[idx].targetAmountCents = max(100, targetAmountCents)
        ws.savingsGoals[idx].targetDate = targetDate
        activeWorkspace = ws
        recordAudit(
            action: "SAVINGS_GOAL_UPDATED",
            entityType: "SavingsGoal",
            entityId: goalId.uuidString,
            summary: "Updated savings goal '\(name)' target to \(AustralianMoneyFormatter.format(cents: targetAmountCents))."
        )
    }

    public func deleteSavingsGoal(id: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.savingsGoals.firstIndex(where: { $0.id == id }) else { return }
        let removedName = ws.savingsGoals[idx].name
        ws.savingsGoals.remove(at: idx)
        activeWorkspace = ws
        recordAudit(
            action: "SAVINGS_GOAL_DELETED",
            entityType: "SavingsGoal",
            entityId: id.uuidString,
            summary: "Deleted savings goal '\(removedName)'."
        )
    }

    public func addSavingsContribution(
        goalId: UUID,
        amountCents: MoneyCents,
        note: String,
        linkedTransactionId: UUID? = nil
    ) {
        guard amountCents > 0 else { return }
        var ws = activeWorkspace
        guard let idx = ws.savingsGoals.firstIndex(where: { $0.id == goalId }) else { return }

        // Prevent double-counting when a savings contribution is already linked to an account transfer transaction
        if let db = sqliteDatabase {
            do {
                let contrib = try db.recordSavingsContribution(
                    tenantId: activeTenantId,
                    goalId: goalId,
                    amountCents: amountCents,
                    contributedAt: Date(),
                    sourceAccountId: ws.savingsGoals[idx].linkedAccountId,
                    linkedTransactionId: linkedTransactionId,
                    note: note
                )
                ws.savingsGoals[idx].contributions.insert(contrib, at: 0)
            } catch {
                statusBannerMessage = error.localizedDescription
                return
            }
        } else {
            let contrib = SavingsContribution(id: UUID(), date: Date(), amountCents: amountCents, note: note)
            ws.savingsGoals[idx].contributions.insert(contrib, at: 0)
        }

        ws.savingsGoals[idx].currentSavedCents = max(0, ws.savingsGoals[idx].currentSavedCents + amountCents)
        activeWorkspace = ws
        recordAudit(
            action: "SAVINGS_CONTRIBUTION_ADDED",
            entityType: "SavingsGoal",
            entityId: goalId.uuidString,
            summary: "Logged \(AustralianMoneyFormatter.format(cents: amountCents)) contribution toward '\(ws.savingsGoals[idx].name)'."
        )
    }

    // MARK: - Accounts & Open Banking CDR Adapter Simulation

    public func addManualAccount(
        institutionName: String,
        nickname: String,
        accountType: FinancialAccountType,
        maskedDigits: String,
        openingBalanceCents: MoneyCents
    ) {
        var ws = activeWorkspace
        let cleanDigits = String(maskedDigits.filter(\.isNumber).suffix(4))
        let masked = "•••• \(cleanDigits.isEmpty ? "0000" : cleanDigits)"
        let acct = FinancialAccount(
            id: UUID(),
            tenantId: activeTenantId,
            institutionName: institutionName,
            nickname: nickname,
            accountType: accountType,
            maskedAccountNumber: masked,
            currencyCode: "AUD",
            availableBalanceCents: openingBalanceCents,
            currentBalanceCents: openingBalanceCents,
            balanceUpdatedAt: Date(),
            connectionStatus: .manual,
            lastSuccessfulSyncAt: Date(),
            lastSyncErrorMessage: nil,
            dataCoverageDescription: "Manual balance & statement import",
            consentRecordId: nil,
            includeInSafeToSpendCash: accountType.isAssetAccount
        )
        ws.accounts.append(acct)
        activeWorkspace = ws
        recordAudit(
            action: "ACCOUNT_ADDED",
            entityType: "FinancialAccount",
            entityId: acct.id.uuidString,
            summary: "Added manual account '\(nickname)' (\(masked))."
        )
    }

    public func renameAccount(accountId: UUID, newNickname: String) {
        var ws = activeWorkspace
        guard let idx = ws.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        ws.accounts[idx].nickname = newNickname
        activeWorkspace = ws
    }

    public func simulateAccountRefreshFailure(accountId: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        ws.accounts[idx].connectionStatus = .cdrRefreshFailed
        ws.accounts[idx].lastSyncErrorMessage = "Provider upstream timeout (HTTP 504). Last known balance preserved."
        activeWorkspace = ws
    }

    public func retryAccountSync(accountId: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        ws.accounts[idx].connectionStatus = isDemoMode ? .demoSynthetic : .manual
        ws.accounts[idx].lastSyncErrorMessage = nil
        ws.accounts[idx].lastSuccessfulSyncAt = Date()
        ws.accounts[idx].balanceUpdatedAt = Date()
        activeWorkspace = ws
        statusBannerMessage = "Account sync recovered cleanly."
    }

    public func disconnectAccountAndRevokeConsent(accountId: UUID) {
        var ws = activeWorkspace
        guard let idx = ws.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        ws.accounts[idx].connectionStatus = .disconnected
        if let consentId = ws.accounts[idx].consentRecordId,
           let cIdx = ws.consentRecords.firstIndex(where: { $0.id == consentId }) {
            ws.consentRecords[cIdx].revokedAt = Date()
            ws.consentRecords[cIdx].statusNote = "Revoked by user — data collection halted"
        }
        activeWorkspace = ws
        recordAudit(
            action: "ACCOUNT_DISCONNECTED",
            entityType: "FinancialAccount",
            entityId: accountId.uuidString,
            summary: "Disconnected account and revoked associated CDR consent."
        )
    }

    // MARK: - Notifications & Calculated Daily Summary Scheduler

    public func markAllNotificationsRead() {
        var ws = activeWorkspace
        for i in ws.notifications.indices {
            ws.notifications[i].isRead = true
        }
        activeWorkspace = ws
    }

    public func updateNotificationPreferences(_ prefs: NotificationPreferences) {
        var ws = activeWorkspace
        ws.notificationPreferences = prefs
        activeWorkspace = ws
        refreshDailyNotificationsAndSchedule()
    }

    /// Generates a fresh, deduplicated daily summary notification from actual calculated `allowanceSummary`
    /// figures and synchronizes OS notification scheduling in the user's Australian time zone.
    public func refreshDailyNotificationsAndSchedule() {
        if usesLiveClock {
            referenceDate = Date()
        }
        recalculateDerivedState()

        var ws = activeWorkspace
        let auCal = AustralianDateHelper.calendar(for: ws.profile.timeZoneId)
        let summaryPayload = DaylightNotificationScheduler.buildDailyEveningSummary(
            tenantId: activeTenantId,
            referenceDate: referenceDate,
            timeZoneId: ws.profile.timeZoneId,
            summary: allowanceSummary,
            preferences: ws.notificationPreferences
        )

        if let existingIdx = ws.notifications.firstIndex(where: {
            $0.categoryTag == "daily_summary" && auCal.isDate($0.createdAt, inSameDayAs: referenceDate)
        }) {
            ws.notifications[existingIdx].title = summaryPayload.title
            ws.notifications[existingIdx].body = summaryPayload.body
        } else if ws.notificationPreferences.dailySummaryEnabled {
            ws.notifications.insert(
                AppNotification(
                    id: UUID(),
                    tenantId: activeTenantId,
                    title: summaryPayload.title,
                    body: summaryPayload.body,
                    categoryTag: summaryPayload.categoryTag,
                    createdAt: referenceDate,
                    isRead: false,
                    notificationType: summaryPayload.categoryTag,
                    targetSectionRawValue: summaryPayload.targetSectionRawValue,
                    eventIdentifier: summaryPayload.eventIdentifier
                ),
                at: 0
            )
        }

        if isDemoMode {
            demoWorkspace = ws
        } else {
            personalWorkspace = ws
        }
        saveWorkspacesIfNeeded()

        syncOSNotificationsInBackground(workspace: ws, summary: allowanceSummary)
    }

    // MARK: - Data Export (Sanitized CSV & JSON) and Account Deletion

    /// Exports user transactions within an optional date range as a formula-injection-safe CSV string.
    public func exportTransactionsAsSanitizedCSV(fromDate: Date? = nil, toDate: Date? = nil) -> String {
        var rows: [String] = [
            "TransactionID,OccurredAtUTC,LocalDateAU,Merchant,RawDescription,Direction,AmountAUD,Category,Kind,Status,PaymentRail,Source,ExcludedFromBudget,UserNote"
        ]
        let iso = ISO8601DateFormatter()
        let filtered = transactions.filter { tx in
            if let fromDate, tx.occurredAt < fromDate { return false }
            if let toDate, tx.occurredAt > toDate { return false }
            return true
        }
        for tx in filtered {
            let amountDollars = String(format: "%.2f", Double(tx.amountCents) / 100.0)
            let localDate = AustralianDateHelper.formatShortDate(tx.occurredAt, timeZoneId: profile.timeZoneId)
            let fields = [
                tx.id.uuidString,
                iso.string(from: tx.occurredAt),
                localDate,
                tx.merchantName,
                tx.rawDescription,
                tx.direction.rawValue,
                amountDollars,
                tx.category.displayName,
                tx.kind.displayName,
                tx.status.displayName,
                tx.paymentRail ?? "",
                tx.source.displayName,
                tx.excludeFromBudget ? "true" : "false",
                tx.userNote
            ].map { FinancialCalculationEngine.sanitizeCSVCell($0) }
            rows.append(fields.joined(separator: ","))
        }
        recordAudit(
            action: "DATA_EXPORT_CSV",
            entityType: "TenantWorkspace",
            entityId: activeTenantId,
            summary: "Exported \(filtered.count) transactions as formula-sanitized CSV."
        )
        return rows.joined(separator: "\n")
    }

    /// Exports the complete workspace snapshot as formatted JSON.
    public func exportWorkspaceAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(activeWorkspace),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        recordAudit(
            action: "DATA_EXPORT_JSON",
            entityType: "TenantWorkspace",
            entityId: activeTenantId,
            summary: "Exported full user data portability archive (JSON)."
        )
        return json
    }

    /// Permanently deletes all personal workspace data from SQLite and disk, resetting to an un-onboarded state.
    public func deleteCurrentWorkspaceData() {
        if isDemoMode {
            resetSyntheticDemoData()
        } else {
            let targetTenant = activeTenantId
            let currentSession = authState.currentSession
            personalWorkspace = Self.makeBlankPersonalWorkspace(
                referenceDate: referenceDate,
                tenantId: targetTenant,
                preferredName: currentSession?.fullName ?? "",
                email: currentSession?.email ?? "",
                onboardingCompleted: currentSession != nil,
                includeDefaultEverydayAccount: currentSession != nil
            )
            try? sqliteDatabase?.deleteTenantWorkspace(tenantId: targetTenant)
            try? sqliteDatabase?.saveTenantSnapshot(personalWorkspace)
            Self.deleteWorkspaceFileFromDisk(tenantId: targetTenant)
            if persistToDisk {
                Task {
                    await DaylightNotificationScheduler.clearAllScheduledOSNotifications()
                }
            }
            refreshWorkspaceCategories()
            recalculateDerivedState()
            if currentSession == nil {
                showingOnboardingSheet = true
            }
            statusBannerMessage = "Your local SQLite personal workspace and financial records have been permanently deleted from this device. No external cloud copy exists."
        }
    }

    // MARK: - Local SQLite + Fallback Disk Persistence

    private static func storageURL(for tenantId: String) -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("daylight_\(tenantId)_v2.json")
    }

    private func saveWorkspacesIfNeeded() {
        do {
            try sqliteDatabase?.saveTenantSnapshot(activeWorkspace)
        } catch {
            persistenceErrorMessage = "Your change could not be saved: \(error.localizedDescription)"
            statusBannerMessage = persistenceErrorMessage
            return
        }
        guard persistToDisk else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url = Self.storageURL(for: activeTenantId) else {
            persistenceErrorMessage = "Your change could not be saved because local storage is unavailable."
            statusBannerMessage = persistenceErrorMessage
            return
        }
        do {
            let data = try encoder.encode(activeWorkspace)
            try data.write(to: url, options: .atomic)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Your change could not be saved: \(error.localizedDescription)"
            statusBannerMessage = persistenceErrorMessage
        }
    }

    private static func loadWorkspaceFromDisk(tenantId: String) -> TenantWorkspaceSnapshot? {
        guard let url = storageURL(for: tenantId),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TenantWorkspaceSnapshot.self, from: data)
    }

    private static func deleteWorkspaceFileFromDisk(tenantId: String) {
        if let url = storageURL(for: tenantId) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Navigation Sections

public enum AppNavigationSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case transactions = "Transactions"
    case budgets = "Budgets"
    case bills = "Bills & Subscriptions"
    case savings = "Savings Goals"
    case insights = "Insights"
    case accounts = "Accounts"
    case settings = "Settings"
    case assistant = "AI Assistant"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .overview: return "sun.max.fill"
        case .transactions: return "list.bullet.rectangle.portrait.fill"
        case .budgets: return "chart.pie.fill"
        case .bills: return "calendar.badge.clock"
        case .savings: return "target"
        case .insights: return "chart.xyaxis.line"
        case .accounts: return "building.columns.fill"
        case .settings: return "gearshape.fill"
        case .assistant: return "sparkles"
        }
    }
}
