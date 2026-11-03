import SwiftUI

public struct ContentView: View {
    @State private var store = DaylightStore()
    @State private var isNavigationBarCompact = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if !store.authState.isSignedIn {
                WelcomeAndAuthContainerView(store: store)
            } else if horizontalSizeClass == .regular {
                splitViewShell
            } else {
                compactTabShell
            }
        }
        .preferredColorScheme(store.profile.themePreference.colorScheme)
        .scrollIndicators(.hidden)
        .task {
            await store.restoreAuthenticatedSessionIfAvailable()
            store.syncLiveReferenceDateAndNotifications()
            if let pendingResponse = DaylightNotificationDelegate.shared.consumePendingResponse() {
                routeNotification(pendingResponse)
            }
            if let sectionArgIdx = ProcessInfo.processInfo.arguments.firstIndex(of: "-section"),
               sectionArgIdx + 1 < ProcessInfo.processInfo.arguments.count {
                let secName = ProcessInfo.processInfo.arguments[sectionArgIdx + 1].lowercased()
                switch secName {
                case "overview", "home": store.selectedSection = .overview
                case "transactions", "activity": store.selectedSection = .transactions
                case "budgets": store.selectedSection = .budgets
                case "bills": store.selectedSection = .bills
                case "savings": store.selectedSection = .savings
                case "insights": store.selectedSection = .insights
                case "accounts": store.selectedSection = .accounts
                case "settings": store.selectedSection = .settings
                case "assistant", "chat": store.selectedSection = .assistant
                default: break
                }
            } else if ProcessInfo.processInfo.arguments.contains("-settings") {
                store.selectedSection = .settings
            } else if ProcessInfo.processInfo.arguments.contains("-insights") {
                store.selectedSection = .insights
            }

            if let sheetArgIdx = ProcessInfo.processInfo.arguments.firstIndex(of: "-sheet"),
               sheetArgIdx + 1 < ProcessInfo.processInfo.arguments.count {
                let sheetName = ProcessInfo.processInfo.arguments[sheetArgIdx + 1].lowercased()
                switch sheetName {
                case "notifications": store.showingNotificationsSheet = true
                case "importer": store.showingStatementImporter = true
                case "onboarding": store.showingOnboardingSheet = true
                case "categories": store.showingCategoriesManagerSheet = true
                case "explainer": store.showingCalculationExplainer = true
                default: break
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.syncLiveReferenceDateAndNotifications()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.syncLiveReferenceDateAndNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .daylightScrollPositionChanged)) { notification in
            guard store.selectedSection != .assistant,
                  let offset = notification.userInfo?["offset"] as? CGFloat else { return }
            let shouldCompact = offset > 12
            guard shouldCompact != isNavigationBarCompact else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                isNavigationBarCompact = shouldCompact
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .daylightNotificationResponse)) { notification in
            guard let userInfo = notification.userInfo as? [String: String] else { return }
            routeNotification(userInfo)
        }
        .sheet(isPresented: $store.showingStatementImporter) {
            StatementImportSheet(store: store)
        }
        .sheet(isPresented: $store.showingNotificationsSheet) {
            NotificationsSheetView(store: store)
        }
        .sheet(isPresented: $store.showingOnboardingSheet) {
            OnboardingView(store: store)
        }
        .sheet(isPresented: $store.showingCategoriesManagerSheet) {
            CategoriesManagementSheet(store: store)
        }
        .sheet(isPresented: $store.showingCalculationExplainer) {
            CalculationExplainerSheet(store: store)
        }
    }

    private func routeNotification(_ userInfo: [String: String]) {
        guard userInfo["tenantId"] == store.activeTenantId,
              let targetSection = userInfo["targetSection"] else {
            return
        }
        switch targetSection {
        case "overview": store.selectedSection = .overview
        case "transactions": store.selectedSection = .transactions
        case "budgets": store.selectedSection = .budgets
        case "bills": store.selectedSection = .bills
        case "savings": store.selectedSection = .savings
        case "insights": store.selectedSection = .insights
        case "accounts": store.selectedSection = .accounts
        case "settings": store.selectedSection = .settings
        case "assistant": store.selectedSection = .assistant
        default: break
        }
    }

    // MARK: - Regular Width (iPad & macOS) Sidebar Split Shell

    private var splitViewShell: some View {
        NavigationSplitView {
            List(
                selection: Binding<AppNavigationSection?>(
                    get: { store.selectedSection },
                    set: { newValue in
                        if let newValue {
                            store.selectedSection = newValue
                        }
                    }
                )
            ) {
                Section("Daily Clarity") {
                    ForEach([AppNavigationSection.overview, .transactions, .assistant, .budgets]) { item in
                        NavigationLink(value: item) {
                            Label(item.rawValue, systemImage: item.symbolName)
                        }
                    }
                }

                Section("Commitments & Planning") {
                    ForEach([AppNavigationSection.bills, .savings, .insights, .accounts]) { item in
                        NavigationLink(value: item) {
                            Label(item.rawValue, systemImage: item.symbolName)
                        }
                    }
                }

                Section("Governance & Privacy") {
                    NavigationLink(value: AppNavigationSection.settings) {
                        Label(AppNavigationSection.settings.rawValue, systemImage: AppNavigationSection.settings.symbolName)
                    }
                }
            }
            .navigationTitle(BrandConfig.appName)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    HStack(spacing: 10) {
                        DaylightAvatarView(
                            avatarImageData: store.profile.avatarImageData,
                            name: store.profile.preferredName,
                            size: 32,
                            isDemo: store.isDemoMode,
                            showBorder: true
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.profile.preferredName.isEmpty ? "Personal Workspace" : store.profile.preferredName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(store.isDemoMode ? "Synthetic AU Demo" : (store.authenticatedSession?.email ?? "Local SQLite"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        DaylightBadge(
                            store.isDemoMode ? "Demo" : "Personal",
                            icon: store.isDemoMode ? "sparkles" : "person.fill",
                            tone: store.isDemoMode ? .demo : .positive
                        )
                        Button("Log out") {
                            Task {
                                await store.logoutAccount()
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial)
            }
        } detail: {
            NavigationStack {
                sectionDestinationView(store.selectedSection)
            }
        }
    }

    // MARK: - Compact Width (iPhone) Floating Glass Navigation Shell

    private var compactTabShell: some View {
        NavigationStack {
            sectionDestinationView(store.selectedSection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.selectedSection != .assistant {
                DaylightGlassNavigationBar(
                    selectedSection: Binding(
                        get: { store.selectedSection },
                        set: { store.selectedSection = $0 }
                    ),
                    isCompact: $isNavigationBarCompact
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.selectedSection)
        .onChange(of: store.selectedSection) { _, _ in
            isNavigationBarCompact = false
        }
    }

    @ViewBuilder
    private func sectionDestinationView(_ section: AppNavigationSection) -> some View {
        switch section {
        case .overview:
            OverviewDashboardView(
                store: store,
                isNavigationBarCompact: $isNavigationBarCompact
            )
        case .transactions:
            TransactionsView(store: store)
        case .budgets:
            BudgetsView(store: store)
        case .bills:
            BillsAndSubscriptionsView(store: store)
        case .savings:
            SavingsGoalsView(store: store)
        case .insights:
            InsightsAnalyticsView(store: store)
        case .accounts:
            AccountsView(store: store)
        case .settings:
            SettingsPrivacyView(store: store)
        case .assistant:
            AIAssistantChatView(store: store)
        }
    }
}

#Preview {
    ContentView()
}
