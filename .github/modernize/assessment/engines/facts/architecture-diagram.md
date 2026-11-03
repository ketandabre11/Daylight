# Architecture Diagram

This report describes the current Daylight Money system design as implemented in the SwiftUI application. It covers the runtime layers, persistence and integrations, major component relationships, data ownership, security boundaries, and principal user flows.

## Application Architecture

<!-- mermaid-checked: no \n, no em-dash/en-dash, no {} in labels, subgraphs are id["label"], arrows are -->|"label"|, all subgraphs closed by end, ids unique -->
~~~mermaid
flowchart TD
    subgraph Client["iOS Client"]
        AppShell["SwiftUI App Shell"]
        Screens["Feature Screens"]
        Design["Daylight Design System"]
    end
    subgraph Domain["Domain and Application Logic"]
        Store["DaylightStore"]
        Models["Financial Models"]
        Calc["Financial Calculation Engine"]
        Intelligence["Analytics and Financial Intelligence"]
    end
    subgraph Data["Local Data Layer"]
        Auth["Authentication Service"]
        SQLite["SQLite Persistence"]
        Vault["Keychain Secure Vault"]
        Import["CSV Import and Export"]
    end
    subgraph Platform["Apple Platform Services"]
        Notifications["UserNotifications"]
        Speech["Speech and Audio"]
        Security["Security Framework"]
    end
    subgraph Files["Local Files"]
        WorkspaceFiles[("Workspace JSON Files")]
        DatabaseFile[("SQLite Database")]
    end

    AppShell -->|"owns navigation and lifecycle"| Screens
    Screens -->|"observes state"| Store
    Screens -->|"renders shared components"| Design
    Store -->|"coordinates"| Models
    Store -->|"recalculates derived state"| Calc
    Store -->|"requests analysis"| Intelligence
    Store -->|"persists workspace snapshots"| SQLite
    Store -->|"handles imports"| Import
    Store -->|"manages sessions"| Auth
    Auth -->|"stores credentials and sessions"| Vault
    Vault -->|"uses platform protection"| Security
    SQLite -->|"writes local records"| DatabaseFile
    Store -->|"legacy and portability fallback"| WorkspaceFiles
    Store -->|"schedules local alerts"| Notifications
    Intelligence -->|"uses local speech input"| Speech
~~~

### Technology Stack Summary

| Layer | Technology | Version | Purpose |
|---|---|---:|---|
| Application | SwiftUI | iOS 26 SDK | Declarative screens, navigation, forms, and adaptive layouts |
| Language | Swift | 5 language mode | Application implementation and value-type domain models |
| Observation | Observation framework | iOS 26 SDK | Observable `DaylightStore` state propagation |
| UI navigation | NavigationStack and NavigationSplitView | iOS 26 SDK | iPhone and iPad navigation |
| Design system | Custom SwiftUI components | Application-owned | Cream and dark themes, cards, glass navigation, typography |
| Domain storage | `MoneyCents` using `Int64` | Application-owned | Deterministic integer-cent financial values |
| Persistence | SQLite via system `SQLite3` | System library | Tenant-scoped durable local financial data |
| Serialization | `Codable` with ISO 8601 dates | Foundation | Workspace snapshots, notification metadata, and import records |
| Authentication | Keychain and local credential service | Security framework | Local sessions and credential storage |
| Password verification | PBKDF2-HMAC-SHA256 | Application-owned | Versioned password verifier with legacy migration |
| Notifications | UserNotifications | iOS 26 SDK | Local daily, budget, and bill reminders |
| Voice input | Speech and AVFoundation | iOS 26 SDK | Optional voice assistant input |
| Financial logic | Calculation, analytics, and intelligence services | Application-owned | Budgets, cash flow, insights, classification, and assistant responses |
| Testing | Swift Testing and XCTest runtime | Xcode project | Financial, persistence, authentication, UI, and regression tests |

### Data Storage & External Services

Daylight is primarily an offline-first local application. SQLite is the authoritative durable store for tenant workspaces, transactions, accounts, budgets, commitments, recurring predictions, categories, imports, notifications, and audit records. Some workspace snapshots are also represented as JSON for compatibility, recovery, and portability. Credentials and active sessions use the Keychain-backed secure vault. The app uses Apple local services for notifications, speech recognition, audio session management, and secure storage. CDR and bank connectivity are represented as local or synthetic sandbox concepts; no live banking API or external financial-data service is currently integrated. The configured remote authentication mode is explicitly unavailable rather than silently falling back to local authentication.

### Key Architectural Decisions

- Uses a single `@MainActor` `DaylightStore` as the application-facing coordinator while keeping calculations and analytics in deterministic, testable services.
- Preserves tenant isolation by carrying `tenantId` through workspace snapshots, persistence operations, notification metadata, and navigation validation.
- Uses integer-cent financial values and explicit Australian calendar and timezone helpers to avoid binary floating-point and date-boundary errors.
- Uses additive SQLite migrations, WAL journaling, foreign keys, and transactional writes to preserve local financial history.

## Component Relationships

<!-- mermaid-checked: no \n, no em-dash/en-dash, no {} in labels, subgraphs are id["label"], arrows are -->|"label"|, all subgraphs closed by end, ids unique -->
~~~mermaid
flowchart LR
    subgraph cPresentation["Presentation"]
        cShell["ContentView"]
        cDashboard["Overview Dashboard"]
        cTransactions["Transactions Screen"]
        cBudgets["Budgets and Bills Screens"]
        cSettings["Settings and Notifications"]
        cAssistant["Assistant Screens"]
    end
    subgraph cCoordination["Application Coordination"]
        cStore["DaylightStore"]
        cAuth["Authentication Service"]
        cNotify["Notification Scheduler"]
        cDelegate["Notification Delegate"]
    end
    subgraph cDomain["Domain Services"]
        cCalc["Financial Calculation Engine"]
        cAnalytics["Spending Analytics"]
        cClassification["Transaction Intelligence"]
        cAssistantEngine["Financial Assistant Engine"]
        cSpeech["Speech Service"]
    end
    subgraph cPersistence["Persistence"]
        cDatabase["SQLite Persistence Database"]
        cVault["Secure Auth Vault"]
        cSnapshots["Workspace Snapshot Files"]
    end
    subgraph cPlatform["Apple Frameworks"]
        cUserNotifications["UserNotifications"]
        cSecurity["Security"]
        cSpeechPlatform["Speech and AVFoundation"]
    end

    cShell -->|"routes sections and session state"| cStore
    cDashboard -->|"reads summaries and commitments"| cStore
    cTransactions -->|"edits and imports records"| cStore
    cBudgets -->|"manages budgets and bills"| cStore
    cSettings -->|"updates profile and preferences"| cStore
    cAssistant -->|"submits local questions"| cAssistantEngine
    cStore -->|"validates and persists mutations"| cDatabase
    cStore -->|"loads fallback snapshots"| cSnapshots
    cStore -->|"registers and restores sessions"| cAuth
    cAuth -->|"stores credentials"| cVault
    cVault -->|"protects secrets"| cSecurity
    cStore -->|"calculates derived state"| cCalc
    cStore -->|"refreshes analytics"| cAnalytics
    cStore -->|"schedules alerts"| cNotify
    cNotify -->|"adds and reconciles requests"| cUserNotifications
    cDelegate -->|"receives taps and foreground events"| cUserNotifications
    cDelegate -->|"hands validated routes to"| cShell
    cTransactions -->|"requests classification and duplicates"| cClassification
    cClassification -->|"uses transaction rules"| cStore
    cAssistantEngine -->|"reads local financial state"| cStore
    cAssistant -->|"captures voice input"| cSpeech
    cSpeech -->|"uses device speech APIs"| cSpeechPlatform
    cCalc -->|"feeds summaries"| cAnalytics
    cCalc -->|"feeds deterministic insights"| cAssistantEngine
~~~

### Component Inventory

| Component | Layer | Type | Responsibility |
|---|---|---|---|
| `MyApp` | Presentation | Application entry point | Creates the SwiftUI application and registers lifecycle integrations |
| `ContentView` | Presentation | Root view and navigation shell | Authentication gate, section routing, adaptive iPhone and iPad navigation, notification deep links |
| `OverviewDashboardView` | Presentation | Feature screen | Safe-to-spend presentation, summaries, upcoming commitments, and dashboard actions |
| `TransactionsView` | Presentation | Feature screen | Search, filtering, editing, splits, categorisation, CSV import, and export |
| `BudgetsAndBillsViews` | Presentation | Feature screens | Budget setup, fixed commitments, recurring predictions, confirmations, and dismissal |
| `SettingsAndNotificationsViews` | Presentation | Feature screen | Profile, workspace, notification preferences, privacy, exports, and account controls |
| `AIAssistantChatView` | Presentation | Feature screen | Local financial question and answer experience |
| `AIVoiceAssistantView` | Presentation | Feature screen | Voice-driven assistant interaction |
| `DaylightStore` | Coordination | Main actor observable coordinator | Owns active workspace state, mutation orchestration, derived refresh, navigation state, and lifecycle |
| `DaylightAuthenticationService` | Coordination | Authentication service | Registration, login, session restore, logout, local provider selection, and credential migration |
| `DaylightNotificationScheduler` | Coordination | Notification service | Permission state, payload creation, deterministic request identifiers, reconciliation, and cancellation |
| `DaylightNotificationDelegate` | Coordination | Apple delegate adapter | Foreground presentation and queued notification response delivery |
| `FinancialModels` | Domain | Codable value models | Transactions, accounts, budgets, commitments, goals, profiles, notifications, and tenant snapshots |
| `FinancialCalculationEngine` | Domain | Pure calculation service | Period boundaries, allowance, budgets, split attribution, imports, recurrence, and financial rules |
| `SpendingAnalyticsService` | Domain | Analytics service | Monthly, weekly, merchant, category, cash-flow, and comparison analytics |
| `TransactionIntelligence` | Domain | Classification services | Merchant recognition, category inference, feedback rules, and duplicate detection |
| `DaylightFinancialAssistantEngine` | Domain | Deterministic assistant | Converts local financial state into structured, evidence-backed responses |
| `DaylightSpeechService` | Domain | Speech adapter | Manages speech authorization, recognition state, and transcription |
| `SQLitePersistenceDatabase` | Persistence | SQLite data access layer | Schema creation, migrations, tenant-scoped reads and writes, indexes, and transactions |
| `DaylightSecureAuthVault` | Persistence | Secure storage adapter | Keychain or in-memory test storage for credentials and sessions |
| Workspace snapshot files | Persistence | JSON file storage | Compatibility fallback, local workspace recovery, and export support |
| Daylight design system | Presentation support | Reusable UI components | Themes, glass surfaces, financial cards, typography, avatars, and adaptive navbar |
| UserNotifications | Platform | Apple framework | Local notification authorization, scheduling, delivery, and response callbacks |
| Security | Platform | Apple framework | Keychain storage and protected credential access |
| Speech and AVFoundation | Platform | Apple frameworks | Voice recognition and audio session management |

### Core Data Ownership

| Data | Authoritative owner | Persistence form |
|---|---|---|
| Active session | Authentication service and secure vault | Keychain data |
| Tenant workspace | `DaylightStore` active workspace snapshot | SQLite plus compatibility JSON |
| Transactions | Active tenant workspace | SQLite payload and indexed lookup fields |
| Accounts and balances | Active tenant workspace | SQLite payload and account records |
| Budgets and commitments | Active tenant workspace | SQLite payloads |
| Recurring predictions | Calculation engine output preserved in workspace | SQLite payloads |
| Categories | SQLite category tables scoped by tenant | Relational records |
| Import issues | Import workflow and SQLite database | Import job records |
| Notification preferences | Workspace profile | Workspace snapshot |
| OS notification requests | UserNotifications scheduler | Device notification center |
| Financial insights | Calculation and analytics services | Derived in memory |

### Primary Runtime Flows

1. **Launch and restoration:** `MyApp` creates the root shell, `ContentView` observes authentication state, the authentication service restores a session from the vault, and `DaylightStore` loads the matching tenant workspace.
2. **Financial mutation:** A feature screen submits a validated mutation to `DaylightStore`; the store verifies tenant ownership and financial invariants, updates the workspace, recalculates derived state, persists the snapshot transactionally, and refreshes affected notifications.
3. **CSV import:** `TransactionsView` supplies statement text and a column mapping; the calculation engine parses records, validates dates and integer-cent amounts, creates deterministic fingerprints, exposes rejected rows for repair, and only imports after confirmation.
4. **Dashboard refresh:** The store recalculates period summaries, category progress, insights, and analytics from the active tenant records using the configured Australian timezone.
5. **Notification interaction:** The scheduler reconciles tenant-scoped local requests; the delegate queues response metadata; `ContentView` consumes and validates the tenant route before changing the selected section.
6. **Recurring commitment lifecycle:** Transactions feed recurrence detection; confirmed and dismissed predictions are preserved in workspace state; user-facing accessors hide dismissed predictions without deleting their persisted history.

### Security and Privacy Boundaries

- Financial records remain local to the device and are separated by tenant identifiers.
- Credentials and sessions are stored through Keychain-backed storage rather than plaintext files.
- Notification payloads support exact-amount masking for lock-screen privacy.
- Notification deep links validate tenant identity before navigation.
- CSV exports sanitize formula-like cell prefixes to reduce spreadsheet formula injection risk.
- Demo data is isolated from personal financial records and is not mixed into personal calculations.

