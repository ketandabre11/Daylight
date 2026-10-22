import SwiftUI

public struct ContentView: View {
    @State private var store = DaylightStore()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        .task {
            await store.restoreAuthenticatedSessionIfAvailable()
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
                    ForEach([AppNavigationSection.overview, .transactions, .budgets]) { item in
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
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack {
                        Circle()
                            .fill(store.isDemoMode ? Color.purple : DaylightTheme.positive)
                            .frame(width: 8, height: 8)
                        Text(store.isDemoMode ? "Demo Mode (Synthetic AU)" : "Personal Workspace")
                            .font(.caption.weight(.semibold))
                        Spacer()
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

    // MARK: - Compact Width (iPhone) Tab Bar Shell (Overview, Transactions, Budgets, Savings, Settings)

    private var compactTabShell: some View {
        TabView(
            selection: Binding(
                get: { store.selectedSection },
                set: { store.selectedSection = $0 }
            )
        ) {
            NavigationStack {
                OverviewDashboardView(store: store)
            }
            .tabItem {
                Label("Overview", systemImage: AppNavigationSection.overview.symbolName)
            }
            .tag(AppNavigationSection.overview)

            NavigationStack {
                TransactionsView(store: store)
            }
            .tabItem {
                Label("Transactions", systemImage: AppNavigationSection.transactions.symbolName)
            }
            .tag(AppNavigationSection.transactions)

            NavigationStack {
                BudgetsView(store: store)
            }
            .tabItem {
                Label("Budgets", systemImage: AppNavigationSection.budgets.symbolName)
            }
            .tag(AppNavigationSection.budgets)

            NavigationStack {
                SavingsGoalsView(store: store)
            }
            .tabItem {
                Label("Savings", systemImage: AppNavigationSection.savings.symbolName)
            }
            .tag(AppNavigationSection.savings)

            NavigationStack {
                SettingsPrivacyView(store: store)
            }
            .tabItem {
                Label("Settings", systemImage: AppNavigationSection.settings.symbolName)
            }
            .tag(AppNavigationSection.settings)
        }
        .tint(DaylightTheme.forestGreen)
    }

    @ViewBuilder
    private func sectionDestinationView(_ section: AppNavigationSection) -> some View {
        switch section {
        case .overview:
            OverviewDashboardView(store: store)
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
        }
    }
}

#Preview {
    ContentView()
}
