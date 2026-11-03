import Foundation
import SQLite3

/// Production-grade local SQLite persistence engine for Daylight Money.
/// Uses Apple's system `libsqlite3` with WAL journaling, schema migrations, indexed tables,
/// and atomic `BEGIN IMMEDIATE ... COMMIT` transactions so all financial edits, CSV imports,
/// budgets, merchant rules, and savings contributions persist across application restarts.
public final class SQLitePersistenceDatabase {
    public enum DatabaseError: Error, LocalizedError, Equatable {
        case openFailed(String)
        case migrationFailed(String)
        case executionFailed(String)
        case serializationFailed(String)
        case constraintViolation(String)
        case categoryInUseCannotDelete(categoryCode: String, transactionCount: Int)
        case unauthorizedWorkspaceAccess(requestedTenant: String, authorizedTenant: String)
        case duplicateSavingsContribution(transactionId: UUID)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let msg): return "SQLite open failed: \(msg)"
            case .migrationFailed(let msg): return "SQLite migration failed: \(msg)"
            case .executionFailed(let msg): return "SQLite execution failed: \(msg)"
            case .serializationFailed(let msg): return "SQLite serialization failed: \(msg)"
            case .constraintViolation(let msg): return "Database constraint violation: \(msg)"
            case .categoryInUseCannotDelete(let code, let count):
                return "Cannot delete category '\(code)' while \(count) transaction(s) reference it. Reassign transactions first."
            case .unauthorizedWorkspaceAccess(let req, let auth):
                return "Unauthorized workspace access: requested '\(req)' while scoped to '\(auth)'."
            case .duplicateSavingsContribution(let txId):
                return "Savings contribution for transaction \(txId.uuidString) is already recorded."
            }
        }
    }

    public static let currentSchemaVersion: Int32 = 3
    public static let systemCategoryTenantScope = "__SYSTEM__"
    private var db: OpaquePointer?
    public let databasePath: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL? = nil, inMemory: Bool = false, targetVersion: Int32 = SQLitePersistenceDatabase.currentSchemaVersion) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        if inMemory {
            self.databasePath = ":memory:"
        } else if let customURL = databaseURL {
            self.databasePath = customURL.path
        } else {
            let fm = FileManager.default
            let baseSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            let folder = baseSupport.appendingPathComponent("DaylightMoneyAU", isDirectory: true)
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            self.databasePath = folder.appendingPathComponent("daylight_finance_v2.sqlite").path
        }

        try openConnection()
        try runMigrationsIfNeeded(targetVersion: targetVersion)
        if targetVersion >= 3 {
            try seedSystemCategoriesIfNeeded()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openConnection() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databasePath, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(message)
        }
        self.db = opened
        try executeRawSQL("PRAGMA journal_mode = WAL;")
        try executeRawSQL("PRAGMA synchronous = NORMAL;")
        try executeRawSQL("PRAGMA foreign_keys = ON;")
    }

    // MARK: - Schema Migrations (v1 -> v2 -> v3)

    private func runMigrationsIfNeeded(targetVersion: Int32) throws {
        try executeRawSQL("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY NOT NULL,
            applied_at TEXT NOT NULL
        );
        """)

        let currentVersion = try queryUserVersion()

        if currentVersion < 1 && targetVersion >= 1 {
            try executeInTransaction {
                // Normalized relational tables per tenant + indexed lookup columns
                try self.executeRawSQL("""
                CREATE TABLE IF NOT EXISTS tenant_workspaces (
                    tenant_id TEXT PRIMARY KEY NOT NULL,
                    schema_version INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    profile_json BLOB NOT NULL,
                    notification_prefs_json BLOB NOT NULL
                );

                CREATE TABLE IF NOT EXISTS financial_accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    institution_name TEXT NOT NULL,
                    nickname TEXT NOT NULL,
                    account_type TEXT NOT NULL,
                    available_balance_cents INTEGER NOT NULL,
                    current_balance_cents INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_accounts_tenant ON financial_accounts(tenant_id);

                CREATE TABLE IF NOT EXISTS transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    reconciliation_fingerprint TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    amount_cents INTEGER NOT NULL,
                    direction TEXT NOT NULL,
                    category_code TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    merchant_name TEXT NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_tx_tenant_date ON transactions(tenant_id, occurred_at DESC);
                CREATE INDEX IF NOT EXISTS idx_tx_tenant_cat ON transactions(tenant_id, category_code);
                CREATE INDEX IF NOT EXISTS idx_tx_tenant_fp ON transactions(tenant_id, account_id, reconciliation_fingerprint);

                CREATE TABLE IF NOT EXISTS category_budgets (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    category_code TEXT NOT NULL,
                    limit_cents INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_budgets_tenant ON category_budgets(tenant_id);

                CREATE TABLE IF NOT EXISTS fixed_commitments (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    category_code TEXT NOT NULL,
                    amount_cents INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_commitments_tenant ON fixed_commitments(tenant_id);

                CREATE TABLE IF NOT EXISTS merchant_rules (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    match_substring TEXT NOT NULL,
                    assigned_category TEXT NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_merchant_rules_tenant ON merchant_rules(tenant_id);

                CREATE TABLE IF NOT EXISTS recurring_predictions (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    merchant_name TEXT NOT NULL,
                    next_expected_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_recurring_tenant ON recurring_predictions(tenant_id);

                CREATE TABLE IF NOT EXISTS savings_goals (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    target_cents INTEGER NOT NULL,
                    current_saved_cents INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_savings_tenant ON savings_goals(tenant_id);

                CREATE TABLE IF NOT EXISTS consent_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    institution_name TEXT NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_consents_tenant ON consent_records(tenant_id);

                CREATE TABLE IF NOT EXISTS import_jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_imports_tenant ON import_jobs(tenant_id, created_at DESC);

                CREATE TABLE IF NOT EXISTS notifications (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_notifications_tenant ON notifications(tenant_id, created_at DESC);

                CREATE TABLE IF NOT EXISTS audit_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    action TEXT NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_audit_tenant ON audit_events(tenant_id, created_at DESC);
                """)
                try self.recordMigrationVersion(1)
            }
        }

        if currentVersion < 2 && targetVersion >= 2 {
            try executeInTransaction {
                try self.executeRawSQL("""
                CREATE TABLE IF NOT EXISTS app_metadata (
                    meta_key TEXT PRIMARY KEY NOT NULL,
                    meta_value TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                """)
                try self.recordMigrationVersion(2)
            }
        }

        if currentVersion < 3 && targetVersion >= 3 {
            try executeInTransaction {
                // Version 3 Migration: Complete relational coverage across all Daylight Money modules
                // without deleting or losing any existing Phase 2 data.
                try self.executeRawSQL("""
                CREATE TABLE IF NOT EXISTS user_profiles (
                    user_id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    normalized_email TEXT NOT NULL,
                    account_status TEXT NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'deleted')),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_user_profiles_tenant ON user_profiles(tenant_id);

                CREATE TABLE IF NOT EXISTS workspace_memberships (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL REFERENCES tenant_workspaces(tenant_id) ON DELETE CASCADE,
                    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
                    role TEXT NOT NULL CHECK (role IN ('owner', 'member', 'viewer')),
                    created_at INTEGER NOT NULL,
                    UNIQUE(tenant_id, user_id)
                );
                CREATE INDEX IF NOT EXISTS idx_memberships_tenant ON workspace_memberships(tenant_id);

                CREATE TABLE IF NOT EXISTS user_preferences (
                    tenant_id TEXT PRIMARY KEY NOT NULL REFERENCES tenant_workspaces(tenant_id) ON DELETE CASCADE,
                    currency_code TEXT NOT NULL DEFAULT 'AUD',
                    locale_identifier TEXT NOT NULL DEFAULT 'en_AU',
                    time_zone_id TEXT NOT NULL DEFAULT 'Australia/Sydney',
                    week_start_day INTEGER NOT NULL DEFAULT 2,
                    theme_preference TEXT NOT NULL DEFAULT 'system',
                    budgeting_method TEXT NOT NULL DEFAULT 'safe_to_spend_pay_cycle',
                    quiet_hours_start INTEGER NOT NULL DEFAULT 22,
                    quiet_hours_end INTEGER NOT NULL DEFAULT 7,
                    hide_exact_amounts INTEGER NOT NULL DEFAULT 1 CHECK (hide_exact_amounts IN (0, 1)),
                    updated_at INTEGER NOT NULL,
                    payload_json BLOB NOT NULL
                );

                CREATE TABLE IF NOT EXISTS app_sessions (
                    session_id TEXT PRIMARY KEY NOT NULL,
                    user_id TEXT NOT NULL,
                    tenant_id TEXT NOT NULL,
                    auth_provider TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    last_active_at INTEGER NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
                );
                CREATE INDEX IF NOT EXISTS idx_sessions_tenant ON app_sessions(tenant_id, is_active);

                CREATE TABLE IF NOT EXISTS transaction_categories (
                    id TEXT PRIMARY KEY NOT NULL,
                    parent_category_id TEXT REFERENCES transaction_categories(id) ON DELETE RESTRICT,
                    tenant_id TEXT NOT NULL,
                    category_code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    icon_name TEXT NOT NULL,
                    display_order INTEGER NOT NULL DEFAULT 0,
                    category_type TEXT NOT NULL CHECK (category_type IN ('expense', 'income', 'transfer')),
                    is_system_default INTEGER NOT NULL DEFAULT 0 CHECK (is_system_default IN (0, 1)),
                    is_custom INTEGER NOT NULL DEFAULT 0 CHECK (is_custom IN (0, 1)),
                    is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    UNIQUE(tenant_id, name)
                );
                CREATE INDEX IF NOT EXISTS idx_categories_tenant_order ON transaction_categories(tenant_id, is_archived, display_order ASC);

                CREATE TABLE IF NOT EXISTS transaction_subcategories (
                    id TEXT PRIMARY KEY NOT NULL,
                    parent_category_id TEXT NOT NULL REFERENCES transaction_categories(id) ON DELETE CASCADE,
                    tenant_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    icon_name TEXT NOT NULL,
                    display_order INTEGER NOT NULL DEFAULT 0,
                    is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    UNIQUE(tenant_id, parent_category_id, name)
                );

                CREATE TABLE IF NOT EXISTS savings_contributions (
                    id TEXT PRIMARY KEY NOT NULL,
                    tenant_id TEXT NOT NULL,
                    goal_id TEXT NOT NULL REFERENCES savings_goals(id) ON DELETE CASCADE,
                    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
                    contributed_at INTEGER NOT NULL,
                    source_account_id TEXT,
                    linked_transaction_id TEXT,
                    note TEXT NOT NULL DEFAULT ''
                );
                CREATE INDEX IF NOT EXISTS idx_savings_contrib_goal ON savings_contributions(tenant_id, goal_id, contributed_at DESC);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_savings_contrib_linked_tx
                    ON savings_contributions(goal_id, linked_transaction_id)
                    WHERE linked_transaction_id IS NOT NULL;

                CREATE TABLE IF NOT EXISTS import_job_issues (
                    id TEXT PRIMARY KEY NOT NULL,
                    import_job_id TEXT NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
                    tenant_id TEXT NOT NULL,
                    row_number INTEGER NOT NULL,
                    sanitized_raw_line TEXT NOT NULL,
                    validation_error TEXT NOT NULL,
                    is_repaired INTEGER NOT NULL DEFAULT 0 CHECK (is_repaired IN (0, 1)),
                    repaired_transaction_id TEXT,
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_import_issues_job ON import_job_issues(tenant_id, import_job_id, is_repaired);
                """)

                // Non-destructive column additions on existing Phase 2 tables
                try self.addColumnIfMissing(table: "financial_accounts", column: "currency_code", definition: "TEXT NOT NULL DEFAULT 'AUD'")
                try self.addColumnIfMissing(table: "financial_accounts", column: "masked_account_number", definition: "TEXT NOT NULL DEFAULT '•••• 0000'")
                try self.addColumnIfMissing(table: "financial_accounts", column: "opening_balance_cents", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "financial_accounts", column: "is_archived", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "financial_accounts", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")

                try self.addColumnIfMissing(table: "transactions", column: "currency_code", definition: "TEXT NOT NULL DEFAULT 'AUD'")
                try self.addColumnIfMissing(table: "transactions", column: "raw_description", definition: "TEXT NOT NULL DEFAULT ''")
                try self.addColumnIfMissing(table: "transactions", column: "posted_at", definition: "INTEGER")
                try self.addColumnIfMissing(table: "transactions", column: "subcategory_id", definition: "TEXT")
                try self.addColumnIfMissing(table: "transactions", column: "classification_confidence", definition: "REAL NOT NULL DEFAULT 1.0")
                try self.addColumnIfMissing(table: "transactions", column: "classification_source", definition: "TEXT NOT NULL DEFAULT 'deterministic_rule'")
                try self.addColumnIfMissing(table: "transactions", column: "user_note", definition: "TEXT NOT NULL DEFAULT ''")
                try self.addColumnIfMissing(table: "transactions", column: "import_source", definition: "TEXT NOT NULL DEFAULT 'manual'")
                try self.addColumnIfMissing(table: "transactions", column: "external_reference", definition: "TEXT")
                try self.addColumnIfMissing(table: "transactions", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "transactions", column: "updated_at", definition: "INTEGER NOT NULL DEFAULT 0")

                try self.addColumnIfMissing(table: "category_budgets", column: "period_type", definition: "TEXT NOT NULL DEFAULT 'fortnightly'")
                try self.addColumnIfMissing(table: "category_budgets", column: "period_start", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "category_budgets", column: "period_end", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "category_budgets", column: "rollover_enabled", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "category_budgets", column: "is_active", definition: "INTEGER NOT NULL DEFAULT 1")
                try self.addColumnIfMissing(table: "category_budgets", column: "updated_at", definition: "INTEGER NOT NULL DEFAULT 0")

                try self.addColumnIfMissing(table: "fixed_commitments", column: "frequency", definition: "TEXT NOT NULL DEFAULT 'monthly'")
                try self.addColumnIfMissing(table: "fixed_commitments", column: "next_due_at", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "fixed_commitments", column: "status", definition: "TEXT NOT NULL DEFAULT 'active'")

                try self.addColumnIfMissing(table: "recurring_predictions", column: "expected_amount_cents", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "recurring_predictions", column: "frequency", definition: "TEXT NOT NULL DEFAULT 'monthly'")
                try self.addColumnIfMissing(table: "recurring_predictions", column: "is_user_confirmed", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "recurring_predictions", column: "status", definition: "TEXT NOT NULL DEFAULT 'active'")
                try self.addColumnIfMissing(table: "recurring_predictions", column: "last_matched_transaction_id", definition: "TEXT")

                try self.addColumnIfMissing(table: "import_jobs", column: "file_name", definition: "TEXT NOT NULL DEFAULT ''")
                try self.addColumnIfMissing(table: "import_jobs", column: "status", definition: "TEXT NOT NULL DEFAULT 'completed'")
                try self.addColumnIfMissing(table: "import_jobs", column: "total_rows", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "import_jobs", column: "accepted_rows", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "import_jobs", column: "rejected_rows", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "import_jobs", column: "duplicate_rows", definition: "INTEGER NOT NULL DEFAULT 0")

                try self.addColumnIfMissing(table: "notifications", column: "notification_type", definition: "TEXT NOT NULL DEFAULT 'general'")
                try self.addColumnIfMissing(table: "notifications", column: "is_read", definition: "INTEGER NOT NULL DEFAULT 0")
                try self.addColumnIfMissing(table: "notifications", column: "related_entity_id", definition: "TEXT")

                try self.executeRawSQL("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_unique_active
                    ON category_budgets(tenant_id, category_code, period_type)
                    WHERE is_active = 1;
                CREATE INDEX IF NOT EXISTS idx_recurring_lookup
                    ON recurring_predictions(tenant_id, status, next_expected_at ASC);
                CREATE INDEX IF NOT EXISTS idx_import_jobs_status
                    ON import_jobs(tenant_id, status, created_at DESC);
                """)

                try self.recordMigrationVersion(3)
            }
        }
    }

    public func migrateToLatest() throws {
        try runMigrationsIfNeeded(targetVersion: Self.currentSchemaVersion)
        try seedSystemCategoriesIfNeeded()
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        guard let db else { return }
        var stmt: OpaquePointer?
        let pragmaSQL = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var exists = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let colNamePtr = sqlite3_column_text(stmt, 1),
               String(cString: colNamePtr) == column {
                exists = true
                break
            }
        }
        if !exists {
            try executeRawSQL("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        }
    }

    public func queryUserVersion() throws -> Int32 {
        guard let db else { throw DatabaseError.openFailed("Database handle closed") }
        var stmt: OpaquePointer?
        let sql = "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0)
        }
        return 0
    }

    private func recordMigrationVersion(_ version: Int32) throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        try executeParameterized(
            sql: "INSERT OR REPLACE INTO schema_migrations (version, applied_at) VALUES (?, ?);",
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, version)
                self.bindText(stmt, index: 2, value: nowISO)
            }
        )
    }

    // MARK: - Metadata Key-Value Store (Seed Flag & Active Workspace Mode)

    public func getMetadata(key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT meta_value FROM app_metadata WHERE meta_key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, index: 1, value: key)
        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    public func setMetadata(key: String, value: String) throws {
        let nowEpoch = Int64(Date().timeIntervalSince1970)
        try executeParameterized(
            sql: "INSERT OR REPLACE INTO app_metadata (meta_key, meta_value, updated_at) VALUES (?, ?, ?);",
            bind: { stmt in
                self.bindText(stmt, index: 1, value: key)
                self.bindText(stmt, index: 2, value: value)
                sqlite3_bind_int64(stmt, 3, nowEpoch)
            }
        )
    }

    // MARK: - Atomic Workspace Save & Load Operations

    public func saveTenantSnapshot(_ snapshot: TenantWorkspaceSnapshot) throws {
        let activeVersion = try queryUserVersion()
        try executeInTransaction {
            let tenantId = snapshot.tenantId
            let nowEpoch = Int64(Date().timeIntervalSince1970)
            let profileData = try self.encoder.encode(snapshot.profile)
            let notifPrefsData = try self.encoder.encode(snapshot.notificationPreferences)

            try self.executeParameterized(
                sql: """
                INSERT OR REPLACE INTO tenant_workspaces
                (tenant_id, schema_version, updated_at, profile_json, notification_prefs_json)
                VALUES (?, ?, ?, ?, ?);
                """,
                bind: { stmt in
                    self.bindText(stmt, index: 1, value: tenantId)
                    sqlite3_bind_int(stmt, 2, activeVersion)
                    sqlite3_bind_int64(stmt, 3, nowEpoch)
                    self.bindBlob(stmt, index: 4, data: profileData)
                    self.bindBlob(stmt, index: 5, data: notifPrefsData)
                }
            )

            if activeVersion >= 3 {
                try self.executeParameterized(
                    sql: """
                    INSERT OR REPLACE INTO user_profiles
                    (user_id, tenant_id, display_name, normalized_email, account_status, created_at, updated_at, payload_json)
                    VALUES (?, ?, ?, ?, 'active', ?, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: snapshot.profile.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: snapshot.profile.preferredName)
                        self.bindText(stmt, index: 4, value: "\(tenantId)@local.daylight.au")
                        sqlite3_bind_int64(stmt, 5, nowEpoch)
                        sqlite3_bind_int64(stmt, 6, nowEpoch)
                        self.bindBlob(stmt, index: 7, data: profileData)
                    }
                )

                try self.executeParameterized(
                    sql: """
                    INSERT OR REPLACE INTO workspace_memberships
                    (id, tenant_id, user_id, role, created_at)
                    VALUES (?, ?, ?, 'owner', ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: "membership:\(tenantId):\(snapshot.profile.id.uuidString)")
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: snapshot.profile.id.uuidString)
                        sqlite3_bind_int64(stmt, 4, nowEpoch)
                    }
                )

                try self.executeParameterized(
                    sql: """
                    INSERT OR REPLACE INTO user_preferences
                    (tenant_id, currency_code, locale_identifier, time_zone_id, week_start_day, theme_preference, budgeting_method, quiet_hours_start, quiet_hours_end, hide_exact_amounts, updated_at, payload_json)
                    VALUES (?, 'AUD', 'en_AU', ?, 2, ?, ?, 22, 7, ?, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: tenantId)
                        self.bindText(stmt, index: 2, value: snapshot.profile.timeZoneId)
                        self.bindText(stmt, index: 3, value: snapshot.profile.themePreference.rawValue)
                        self.bindText(stmt, index: 4, value: snapshot.profile.preferredBudgetingMethod.rawValue)
                        sqlite3_bind_int(stmt, 5, snapshot.notificationPreferences.hideExactAmountsInPreviews ? 1 : 0)
                        sqlite3_bind_int64(stmt, 6, nowEpoch)
                        self.bindBlob(stmt, index: 7, data: notifPrefsData)
                    }
                )
            }

            // Replace tenant rows atomically inside the active SQLite transaction
            var tablesToClear = [
                "financial_accounts",
                "transactions",
                "category_budgets",
                "fixed_commitments",
                "merchant_rules",
                "recurring_predictions",
                "savings_goals",
                "consent_records",
                "import_jobs",
                "notifications",
                "audit_events"
            ]
            if activeVersion >= 3 {
                tablesToClear.insert("savings_contributions", at: 6)
            }
            for table in tablesToClear {
                try self.executeParameterized(
                    sql: "DELETE FROM \(table) WHERE tenant_id = ?;",
                    bind: { stmt in self.bindText(stmt, index: 1, value: tenantId) }
                )
            }

            // 1. Accounts
            for acct in snapshot.accounts {
                let blob = try self.encoder.encode(acct)
                try self.executeParameterized(
                    sql: """
                    INSERT INTO financial_accounts
                    (id, tenant_id, institution_name, nickname, account_type, available_balance_cents, current_balance_cents, updated_at, payload_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: acct.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: acct.institutionName)
                        self.bindText(stmt, index: 4, value: acct.nickname)
                        self.bindText(stmt, index: 5, value: acct.accountType.rawValue)
                        sqlite3_bind_int64(stmt, 6, acct.availableBalanceCents)
                        sqlite3_bind_int64(stmt, 7, acct.currentBalanceCents)
                        sqlite3_bind_int64(stmt, 8, Int64(acct.balanceUpdatedAt.timeIntervalSince1970))
                        self.bindBlob(stmt, index: 9, data: blob)
                    }
                )
            }

            // 2. Transactions
            for tx in snapshot.transactions {
                let blob = try self.encoder.encode(tx)
                try self.executeParameterized(
                    sql: """
                    INSERT INTO transactions
                    (id, tenant_id, account_id, reconciliation_fingerprint, occurred_at, amount_cents, direction, category_code, kind, status, merchant_name, payload_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: tx.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: tx.accountId.uuidString)
                        self.bindText(stmt, index: 4, value: tx.reconciliationFingerprint)
                        sqlite3_bind_int64(stmt, 5, Int64(tx.occurredAt.timeIntervalSince1970))
                        sqlite3_bind_int64(stmt, 6, tx.amountCents)
                        self.bindText(stmt, index: 7, value: tx.direction.rawValue)
                        self.bindText(stmt, index: 8, value: tx.category.rawValue)
                        self.bindText(stmt, index: 9, value: tx.kind.rawValue)
                        self.bindText(stmt, index: 10, value: tx.status.rawValue)
                        self.bindText(stmt, index: 11, value: tx.merchantName)
                        self.bindBlob(stmt, index: 12, data: blob)
                    }
                )
            }

            // 3. Category Budgets
            for b in snapshot.categoryBudgets {
                let blob = try self.encoder.encode(b)
                try self.executeParameterized(
                    sql: "INSERT INTO category_budgets (id, tenant_id, category_code, limit_cents, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: b.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: b.category.rawValue)
                        sqlite3_bind_int64(stmt, 4, b.limitCents)
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }

            // 4. Fixed Commitments
            for c in snapshot.fixedCommitments {
                let blob = try self.encoder.encode(c)
                try self.executeParameterized(
                    sql: "INSERT INTO fixed_commitments (id, tenant_id, category_code, amount_cents, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: c.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: c.category.rawValue)
                        sqlite3_bind_int64(stmt, 4, c.amountCents)
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }

            // 5. Merchant Rules
            for r in snapshot.merchantRules {
                let blob = try self.encoder.encode(r)
                try self.executeParameterized(
                    sql: "INSERT INTO merchant_rules (id, tenant_id, match_substring, assigned_category, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: r.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: r.matchSubstring)
                        self.bindText(stmt, index: 4, value: r.assignedCategory.rawValue)
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }

            // 6. Recurring Predictions
            for p in snapshot.recurringPredictions {
                let blob = try self.encoder.encode(p)
                try self.executeParameterized(
                    sql: "INSERT INTO recurring_predictions (id, tenant_id, merchant_name, next_expected_at, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: p.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: p.merchantName)
                        sqlite3_bind_int64(stmt, 4, Int64(p.nextExpectedDate.timeIntervalSince1970))
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }

            // 7. Savings Goals
            for g in snapshot.savingsGoals {
                let blob = try self.encoder.encode(g)
                try self.executeParameterized(
                    sql: "INSERT INTO savings_goals (id, tenant_id, target_cents, current_saved_cents, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: g.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        sqlite3_bind_int64(stmt, 3, g.targetAmountCents)
                        sqlite3_bind_int64(stmt, 4, g.currentSavedCents)
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
                if activeVersion >= 3 {
                    for contrib in g.contributions where contrib.amountCents > 0 {
                        try self.executeParameterized(
                            sql: """
                            INSERT OR REPLACE INTO savings_contributions
                            (id, tenant_id, goal_id, amount_cents, contributed_at, note)
                            VALUES (?, ?, ?, ?, ?, ?);
                            """,
                            bind: { stmt in
                                self.bindText(stmt, index: 1, value: contrib.id.uuidString)
                                self.bindText(stmt, index: 2, value: tenantId)
                                self.bindText(stmt, index: 3, value: g.id.uuidString)
                                sqlite3_bind_int64(stmt, 4, contrib.amountCents)
                                sqlite3_bind_int64(stmt, 5, Int64(contrib.date.timeIntervalSince1970))
                                self.bindText(stmt, index: 6, value: contrib.note)
                            }
                        )
                    }
                }
            }

            // 8. Consent Records
            for cr in snapshot.consentRecords {
                let blob = try self.encoder.encode(cr)
                try self.executeParameterized(
                    sql: "INSERT INTO consent_records (id, tenant_id, institution_name, payload_json) VALUES (?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: cr.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: cr.institutionName)
                        self.bindBlob(stmt, index: 4, data: blob)
                    }
                )
            }

            // 9. Import Jobs
            for job in snapshot.importJobs {
                let blob = try self.encoder.encode(job)
                try self.executeParameterized(
                    sql: "INSERT INTO import_jobs (id, tenant_id, idempotency_key, created_at, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: job.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: job.idempotencyKey)
                        sqlite3_bind_int64(stmt, 4, Int64(job.createdAt.timeIntervalSince1970))
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }

            // 10. Notifications
            for n in snapshot.notifications {
                let blob = try self.encoder.encode(n)
                try self.executeParameterized(
                    sql: "INSERT INTO notifications (id, tenant_id, created_at, payload_json) VALUES (?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: n.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        sqlite3_bind_int64(stmt, 3, Int64(n.createdAt.timeIntervalSince1970))
                        self.bindBlob(stmt, index: 4, data: blob)
                    }
                )
            }

            // 11. Audit Events
            for ev in snapshot.auditEvents {
                let blob = try self.encoder.encode(ev)
                try self.executeParameterized(
                    sql: "INSERT INTO audit_events (id, tenant_id, created_at, action, payload_json) VALUES (?, ?, ?, ?, ?);",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: ev.id.uuidString)
                        self.bindText(stmt, index: 2, value: tenantId)
                        sqlite3_bind_int64(stmt, 3, Int64(ev.createdAt.timeIntervalSince1970))
                        self.bindText(stmt, index: 4, value: ev.action)
                        self.bindBlob(stmt, index: 5, data: blob)
                    }
                )
            }
        }
    }

    public func loadTenantSnapshot(tenantId: String) throws -> TenantWorkspaceSnapshot? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT profile_json, notification_prefs_json FROM tenant_workspaces WHERE tenant_id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, index: 1, value: tenantId)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let profileBlob = columnBlob(stmt, index: 0),
              let notifBlob = columnBlob(stmt, index: 1) else {
            return nil
        }

        let profile = try decoder.decode(UserProfile.self, from: profileBlob)
        let notifPrefs = try decoder.decode(NotificationPreferences.self, from: notifBlob)

        let accounts: [FinancialAccount] = try queryPayloads(
            sql: "SELECT payload_json FROM financial_accounts WHERE tenant_id = ? ORDER BY updated_at DESC;",
            tenantId: tenantId
        )
        let transactions: [TransactionRecord] = try queryPayloads(
            sql: "SELECT payload_json FROM transactions WHERE tenant_id = ? ORDER BY occurred_at DESC;",
            tenantId: tenantId
        )
        let categoryBudgets: [CategoryBudget] = try queryPayloads(
            sql: "SELECT payload_json FROM category_budgets WHERE tenant_id = ?;",
            tenantId: tenantId
        )
        let fixedCommitments: [FixedCommitment] = try queryPayloads(
            sql: "SELECT payload_json FROM fixed_commitments WHERE tenant_id = ?;",
            tenantId: tenantId
        )
        let merchantRules: [MerchantRule] = try queryPayloads(
            sql: "SELECT payload_json FROM merchant_rules WHERE tenant_id = ?;",
            tenantId: tenantId
        )
        let recurringPredictions: [RecurringPaymentPrediction] = try queryPayloads(
            sql: "SELECT payload_json FROM recurring_predictions WHERE tenant_id = ? ORDER BY next_expected_at ASC;",
            tenantId: tenantId
        )
        let savingsGoals: [SavingsGoal] = try queryPayloads(
            sql: "SELECT payload_json FROM savings_goals WHERE tenant_id = ?;",
            tenantId: tenantId
        )
        let consentRecords: [ConsentRecord] = try queryPayloads(
            sql: "SELECT payload_json FROM consent_records WHERE tenant_id = ?;",
            tenantId: tenantId
        )
        let importJobs: [ImportJobRecord] = try queryPayloads(
            sql: "SELECT payload_json FROM import_jobs WHERE tenant_id = ? ORDER BY created_at DESC;",
            tenantId: tenantId
        )
        let notifications: [AppNotification] = try queryPayloads(
            sql: "SELECT payload_json FROM notifications WHERE tenant_id = ? ORDER BY created_at DESC;",
            tenantId: tenantId
        )
        let auditEvents: [AuditEvent] = try queryPayloads(
            sql: "SELECT payload_json FROM audit_events WHERE tenant_id = ? ORDER BY created_at DESC;",
            tenantId: tenantId
        )

        return TenantWorkspaceSnapshot(
            tenantId: tenantId,
            profile: profile,
            accounts: accounts,
            consentRecords: consentRecords,
            transactions: transactions,
            merchantRules: merchantRules,
            fixedCommitments: fixedCommitments,
            categoryBudgets: categoryBudgets,
            recurringPredictions: recurringPredictions,
            savingsGoals: savingsGoals,
            notificationPreferences: notifPrefs,
            notifications: notifications,
            importJobs: importJobs,
            auditEvents: auditEvents,
            processedIdempotencyKeys: importJobs.map(\.idempotencyKey)
        )
    }

    public func deleteTenantWorkspace(tenantId: String) throws {
        let activeVersion = try queryUserVersion()
        try executeInTransaction {
            var tables = [
                "financial_accounts",
                "transactions",
                "category_budgets",
                "fixed_commitments",
                "merchant_rules",
                "recurring_predictions",
                "savings_goals",
                "consent_records",
                "import_jobs",
                "notifications",
                "audit_events",
                "tenant_workspaces"
            ]
            if activeVersion >= 3 {
                tables = [
                    "savings_contributions",
                    "import_job_issues",
                    "transaction_subcategories",
                    "transaction_categories",
                    "app_sessions",
                    "workspace_memberships",
                    "user_preferences",
                    "user_profiles"
                ] + tables
            }
            for table in tables {
                try self.executeParameterized(
                    sql: "DELETE FROM \(table) WHERE tenant_id = ?;",
                    bind: { stmt in self.bindText(stmt, index: 1, value: tenantId) }
                )
            }
        }
    }

    // MARK: - Module D: Australian System Category Seeding & Custom Category Operations

    /// Idempotently seeds default Australian Expense, Income, and Transfer categories into `transaction_categories`.
    /// Uses `INSERT OR IGNORE` so repeated app launches never duplicate categories or overwrite custom edits.
    public func seedSystemCategoriesIfNeeded() throws {
        let nowEpoch = Int64(Date().timeIntervalSince1970)
        struct SeedSpec {
            let code: String
            let name: String
            let icon: String
            let order: Int
            let type: TransactionCategoryType
        }

        let seeds: [SeedSpec] = [
            // Expenses
            SeedSpec(code: AustralianCategory.groceries.rawValue, name: "Groceries", icon: "cart.fill", order: 10, type: .expense),
            SeedSpec(code: AustralianCategory.cafesAndTakeaway.rawValue, name: "Dining & Coffee", icon: "cup.and.saucer.fill", order: 20, type: .expense),
            SeedSpec(code: AustralianCategory.publicTransport.rawValue, name: "Transport", icon: "tram.fill", order: 30, type: .expense),
            SeedSpec(code: AustralianCategory.fuelTollsVehicle.rawValue, name: "Fuel & Parking", icon: "fuelpump.fill", order: 40, type: .expense),
            SeedSpec(code: AustralianCategory.rentAndMortgage.rawValue, name: "Rent & Mortgage", icon: "house.fill", order: 50, type: .expense),
            SeedSpec(code: AustralianCategory.utilitiesAndInternet.rawValue, name: "Utilities", icon: "bolt.fill", order: 60, type: .expense),
            SeedSpec(code: AustralianCategory.mobilePhone.rawValue, name: "Phone & Internet", icon: "wifi", order: 70, type: .expense),
            SeedSpec(code: AustralianCategory.shoppingRetail.rawValue, name: "Shopping", icon: "bag.fill", order: 80, type: .expense),
            SeedSpec(code: AustralianCategory.healthcareMedicare.rawValue, name: "Health & Pharmacy", icon: "cross.case.fill", order: 90, type: .expense),
            SeedSpec(code: AustralianCategory.insurance.rawValue, name: "Insurance", icon: "shield.lefthalf.filled", order: 100, type: .expense),
            SeedSpec(code: AustralianCategory.streamingSubscriptions.rawValue, name: "Entertainment & Subscriptions", icon: "tv.fill", order: 110, type: .expense),
            SeedSpec(code: AustralianCategory.childcareEducation.rawValue, name: "Education", icon: "graduationcap.fill", order: 120, type: .expense),
            SeedSpec(code: AustralianCategory.domesticTravelHolidays.rawValue, name: "Travel", icon: "airplane", order: 130, type: .expense),
            SeedSpec(code: AustralianCategory.gymFitness.rawValue, name: "Personal Care", icon: "sparkles", order: 140, type: .expense),
            SeedSpec(code: "pets_vet", name: "Pets", icon: "pawprint.fill", order: 150, type: .expense),
            SeedSpec(code: "gifts_donations", name: "Gifts & Donations", icon: "gift.fill", order: 160, type: .expense),
            SeedSpec(code: AustralianCategory.bankFeesInterestRefunds.rawValue, name: "Fees & Charges", icon: "banknote", order: 170, type: .expense),
            SeedSpec(code: AustralianCategory.cashAndUnclassified.rawValue, name: "Cash & Unclassified", icon: "questionmark.circle.fill", order: 180, type: .expense),
            // Income
            SeedSpec(code: AustralianCategory.salaryWagesIncome.rawValue, name: "Salary & Wages", icon: "dollarsign.circle.fill", order: 200, type: .income),
            SeedSpec(code: AustralianCategory.governmentPayments.rawValue, name: "Government Payments", icon: "building.columns.fill", order: 210, type: .income),
            SeedSpec(code: "freelance_business", name: "Freelance & Business", icon: "briefcase.fill", order: 220, type: .income),
            SeedSpec(code: "interest_income", name: "Interest", icon: "percent", order: 230, type: .income),
            SeedSpec(code: "investment_income", name: "Investment Income", icon: "chart.line.uptrend.xyaxis", order: 240, type: .income),
            SeedSpec(code: "refunds_reimbursements", name: "Refunds & Reimbursements", icon: "arrow.uturn.backward.circle.fill", order: 250, type: .income),
            // Non-spending movements
            SeedSpec(code: AustralianCategory.ownAccountTransfer.rawValue, name: "Own-Account Transfer", icon: "arrow.left.arrow.right.circle.fill", order: 300, type: .transfer),
            SeedSpec(code: AustralianCategory.creditCardRepayment.rawValue, name: "Credit-Card Repayment", icon: "creditcard.and.123", order: 310, type: .transfer),
            SeedSpec(code: AustralianCategory.personalLoansDebt.rawValue, name: "Loan Drawdown or Repayment", icon: "arrow.triangle.2.circlepath.circle.fill", order: 320, type: .transfer)
        ]

        try executeInTransaction {
            for s in seeds {
                let stableId = "system:\(s.code)"
                try self.executeParameterized(
                    sql: """
                    INSERT OR IGNORE INTO transaction_categories
                    (id, parent_category_id, tenant_id, category_code, name, icon_name, display_order, category_type, is_system_default, is_custom, is_archived, created_at, updated_at)
                    VALUES (?, NULL, ?, ?, ?, ?, ?, ?, 1, 0, 0, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: stableId)
                        self.bindText(stmt, index: 2, value: Self.systemCategoryTenantScope)
                        self.bindText(stmt, index: 3, value: s.code)
                        self.bindText(stmt, index: 4, value: s.name)
                        self.bindText(stmt, index: 5, value: s.icon)
                        sqlite3_bind_int(stmt, 6, Int32(s.order))
                        self.bindText(stmt, index: 7, value: s.type.rawValue)
                        sqlite3_bind_int64(stmt, 8, nowEpoch)
                        sqlite3_bind_int64(stmt, 9, nowEpoch)
                    }
                )
            }
        }
    }

    /// Returns global system categories (`__SYSTEM__`) plus workspace-scoped custom categories for `tenantId`.
    public func fetchCategories(forTenant tenantId: String, includeArchived: Bool = false) throws -> [TransactionCategoryRecord] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let archiveClause = includeArchived ? "" : "AND is_archived = 0"
        let sql = """
        SELECT id, parent_category_id, tenant_id, category_code, name, icon_name, display_order, category_type, is_system_default, is_custom, is_archived, created_at, updated_at
        FROM transaction_categories
        WHERE (tenant_id = ? OR tenant_id = ?) \(archiveClause)
        ORDER BY display_order ASC, name ASC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            return []
        }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: Self.systemCategoryTenantScope)
        bindText(prepared, index: 2, value: tenantId)

        var records: [TransactionCategoryRecord] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            let id = columnText(prepared, index: 0)
            let parentId = sqlite3_column_type(prepared, 1) == SQLITE_NULL ? nil : columnText(prepared, index: 1)
            let rowTenant = columnText(prepared, index: 2)
            let code = columnText(prepared, index: 3)
            let name = columnText(prepared, index: 4)
            let icon = columnText(prepared, index: 5)
            let order = Int(sqlite3_column_int(prepared, 6))
            let typeRaw = columnText(prepared, index: 7)
            let isSys = sqlite3_column_int(prepared, 8) == 1
            let isCust = sqlite3_column_int(prepared, 9) == 1
            let isArch = sqlite3_column_int(prepared, 10) == 1
            let created = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(prepared, 11)))
            let updated = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(prepared, 12)))

            records.append(
                TransactionCategoryRecord(
                    id: id,
                    parentCategoryId: parentId,
                    tenantId: rowTenant,
                    categoryCode: code,
                    name: name,
                    iconName: icon,
                    displayOrder: order,
                    categoryType: TransactionCategoryType(rawValue: typeRaw) ?? .expense,
                    isSystemDefault: isSys,
                    isCustom: isCust,
                    isArchived: isArch,
                    createdAt: created,
                    updatedAt: updated
                )
            )
        }
        return records
    }

    public func createCustomCategory(
        tenantId: String,
        name: String,
        iconName: String,
        categoryType: TransactionCategoryType,
        displayOrder: Int = 190,
        parentCategoryId: String? = nil
    ) throws -> TransactionCategoryRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseError.constraintViolation("Category name cannot be empty.")
        }
        let slug = trimmed.lowercased().replacingOccurrences(of: " ", with: "_")
        let code = "custom_\(slug)"
        let id = "custom:\(tenantId):\(UUID().uuidString.lowercased())"
        let now = Date()
        let nowEpoch = Int64(now.timeIntervalSince1970)

        try executeParameterized(
            sql: """
            INSERT INTO transaction_categories
            (id, parent_category_id, tenant_id, category_code, name, icon_name, display_order, category_type, is_system_default, is_custom, is_archived, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 1, 0, ?, ?);
            """,
            bind: { stmt in
                self.bindText(stmt, index: 1, value: id)
                if let parentCategoryId {
                    self.bindText(stmt, index: 2, value: parentCategoryId)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                self.bindText(stmt, index: 3, value: tenantId)
                self.bindText(stmt, index: 4, value: code)
                self.bindText(stmt, index: 5, value: trimmed)
                self.bindText(stmt, index: 6, value: iconName)
                sqlite3_bind_int(stmt, 7, Int32(displayOrder))
                self.bindText(stmt, index: 8, value: categoryType.rawValue)
                sqlite3_bind_int64(stmt, 9, nowEpoch)
                sqlite3_bind_int64(stmt, 10, nowEpoch)
            }
        )

        return TransactionCategoryRecord(
            id: id,
            parentCategoryId: parentCategoryId,
            tenantId: tenantId,
            categoryCode: code,
            name: trimmed,
            iconName: iconName,
            displayOrder: displayOrder,
            categoryType: categoryType,
            isSystemDefault: false,
            isCustom: true,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
    }

    public func updateCustomCategory(
        categoryId: String,
        tenantId: String,
        newName: String? = nil,
        newDisplayOrder: Int? = nil,
        isArchived: Bool? = nil
    ) throws {
        let existing = try fetchCategories(forTenant: tenantId, includeArchived: true)
        guard let target = existing.first(where: { $0.id == categoryId && $0.tenantId == tenantId }) else {
            throw DatabaseError.unauthorizedWorkspaceAccess(requestedTenant: categoryId, authorizedTenant: tenantId)
        }
        let updatedName = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? target.name
        let updatedOrder = newDisplayOrder ?? target.displayOrder
        let updatedArchived = isArchived ?? target.isArchived
        let nowEpoch = Int64(Date().timeIntervalSince1970)

        try executeParameterized(
            sql: """
            UPDATE transaction_categories
            SET name = ?, display_order = ?, is_archived = ?, updated_at = ?
            WHERE id = ? AND tenant_id = ?;
            """,
            bind: { stmt in
                self.bindText(stmt, index: 1, value: updatedName)
                sqlite3_bind_int(stmt, 2, Int32(updatedOrder))
                sqlite3_bind_int(stmt, 3, updatedArchived ? 1 : 0)
                sqlite3_bind_int64(stmt, 4, nowEpoch)
                self.bindText(stmt, index: 5, value: categoryId)
                self.bindText(stmt, index: 6, value: tenantId)
            }
        )
    }

    /// Prevents deleting a category referenced by transactions unless `reassignToCategory` is provided.
    public func deleteCustomCategory(
        categoryId: String,
        tenantId: String,
        reassignToCategory: AustralianCategory? = nil
    ) throws {
        let existing = try fetchCategories(forTenant: tenantId, includeArchived: true)
        guard let target = existing.first(where: { $0.id == categoryId && $0.tenantId == tenantId && $0.isCustom }) else {
            throw DatabaseError.unauthorizedWorkspaceAccess(requestedTenant: categoryId, authorizedTenant: tenantId)
        }

        let txCount = try countTransactionsReferencingCategory(tenantId: tenantId, categoryCode: target.categoryCode)
        if txCount > 0 && reassignToCategory == nil {
            throw DatabaseError.categoryInUseCannotDelete(categoryCode: target.categoryCode, transactionCount: txCount)
        }

        try executeInTransaction {
            if let replacement = reassignToCategory, txCount > 0 {
                try self.executeParameterized(
                    sql: "UPDATE transactions SET category_code = ? WHERE tenant_id = ? AND category_code = ?;",
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: replacement.rawValue)
                        self.bindText(stmt, index: 2, value: tenantId)
                        self.bindText(stmt, index: 3, value: target.categoryCode)
                    }
                )
            }
            try self.executeParameterized(
                sql: "DELETE FROM transaction_categories WHERE id = ? AND tenant_id = ? AND is_custom = 1;",
                bind: { stmt in
                    self.bindText(stmt, index: 1, value: categoryId)
                    self.bindText(stmt, index: 2, value: tenantId)
                }
            )
        }
    }

    public func countTransactionsReferencingCategory(tenantId: String, categoryCode: String) throws -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM transactions WHERE tenant_id = ? AND category_code = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else { return 0 }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: tenantId)
        bindText(prepared, index: 2, value: categoryCode)
        if sqlite3_step(prepared) == SQLITE_ROW {
            return Int(sqlite3_column_int(prepared, 0))
        }
        return 0
    }

    // MARK: - Module F: Savings Contributions with Linked-Transaction Deduplication

    /// Inserts a savings contribution into `savings_contributions` and prevents double-counting if `linkedTransactionId`
    /// has already been recorded for the same savings goal.
    public func recordSavingsContribution(
        tenantId: String,
        goalId: UUID,
        amountCents: MoneyCents,
        contributedAt: Date = Date(),
        sourceAccountId: UUID? = nil,
        linkedTransactionId: UUID? = nil,
        note: String = ""
    ) throws -> SavingsContribution {
        guard amountCents > 0 else {
            throw DatabaseError.constraintViolation("Savings contribution amount must be positive (> 0 cents).")
        }

        if let linkedTxId = linkedTransactionId,
           try hasSavingsContributionForTransaction(goalId: goalId, linkedTransactionId: linkedTxId) {
            throw DatabaseError.duplicateSavingsContribution(transactionId: linkedTxId)
        }

        let contrib = SavingsContribution(id: UUID(), date: contributedAt, amountCents: amountCents, note: note)
        try executeParameterized(
            sql: """
            INSERT INTO savings_contributions
            (id, tenant_id, goal_id, amount_cents, contributed_at, source_account_id, linked_transaction_id, note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bind: { stmt in
                self.bindText(stmt, index: 1, value: contrib.id.uuidString)
                self.bindText(stmt, index: 2, value: tenantId)
                self.bindText(stmt, index: 3, value: goalId.uuidString)
                sqlite3_bind_int64(stmt, 4, amountCents)
                sqlite3_bind_int64(stmt, 5, Int64(contributedAt.timeIntervalSince1970))
                if let sourceAccountId {
                    self.bindText(stmt, index: 6, value: sourceAccountId.uuidString)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                if let linkedTransactionId {
                    self.bindText(stmt, index: 7, value: linkedTransactionId.uuidString)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                self.bindText(stmt, index: 8, value: note)
            }
        )
        return contrib
    }

    private func hasSavingsContributionForTransaction(goalId: UUID, linkedTransactionId: UUID) throws -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM savings_contributions WHERE goal_id = ? AND linked_transaction_id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else { return false }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: goalId.uuidString)
        bindText(prepared, index: 2, value: linkedTransactionId.uuidString)
        if sqlite3_step(prepared) == SQLITE_ROW {
            return sqlite3_column_int(prepared, 0) > 0
        }
        return false
    }

    // MARK: - Module H: Persistent Repairable Import Job Issues

    public func saveImportJobIssues(_ issues: [ImportJobIssueRecord]) throws {
        try executeInTransaction {
            for issue in issues {
                try self.executeParameterized(
                    sql: """
                    INSERT OR REPLACE INTO import_job_issues
                    (id, import_job_id, tenant_id, row_number, sanitized_raw_line, validation_error, is_repaired, repaired_transaction_id, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bind: { stmt in
                        self.bindText(stmt, index: 1, value: issue.id.uuidString)
                        self.bindText(stmt, index: 2, value: issue.importJobId.uuidString)
                        self.bindText(stmt, index: 3, value: issue.tenantId)
                        sqlite3_bind_int(stmt, 4, Int32(issue.rowNumber))
                        self.bindText(stmt, index: 5, value: issue.sanitizedRawLine)
                        self.bindText(stmt, index: 6, value: issue.validationError)
                        sqlite3_bind_int(stmt, 7, issue.isRepaired ? 1 : 0)
                        if let repairedTx = issue.repairedTransactionId {
                            self.bindText(stmt, index: 8, value: repairedTx.uuidString)
                        } else {
                            sqlite3_bind_null(stmt, 8)
                        }
                        sqlite3_bind_int64(stmt, 9, Int64(issue.createdAt.timeIntervalSince1970))
                    }
                )
            }
        }
    }

    public func fetchImportJobIssues(tenantId: String, importJobId: UUID? = nil) throws -> [ImportJobIssueRecord] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql: String
        if importJobId != nil {
            sql = "SELECT id, import_job_id, tenant_id, row_number, sanitized_raw_line, validation_error, is_repaired, repaired_transaction_id, created_at FROM import_job_issues WHERE tenant_id = ? AND import_job_id = ? ORDER BY row_number ASC;"
        } else {
            sql = "SELECT id, import_job_id, tenant_id, row_number, sanitized_raw_line, validation_error, is_repaired, repaired_transaction_id, created_at FROM import_job_issues WHERE tenant_id = ? ORDER BY created_at DESC, row_number ASC;"
        }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else { return [] }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: tenantId)
        if let importJobId {
            bindText(prepared, index: 2, value: importJobId.uuidString)
        }
        var results: [ImportJobIssueRecord] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            let id = UUID(uuidString: columnText(prepared, index: 0)) ?? UUID()
            let jobId = UUID(uuidString: columnText(prepared, index: 1)) ?? UUID()
            let tId = columnText(prepared, index: 2)
            let rowNum = Int(sqlite3_column_int(prepared, 3))
            let rawLine = columnText(prepared, index: 4)
            let err = columnText(prepared, index: 5)
            let isRep = sqlite3_column_int(prepared, 6) == 1
            let repTx = sqlite3_column_type(prepared, 7) == SQLITE_NULL ? nil : UUID(uuidString: columnText(prepared, index: 7))
            let created = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(prepared, 8)))
            results.append(
                ImportJobIssueRecord(
                    id: id,
                    importJobId: jobId,
                    tenantId: tId,
                    rowNumber: rowNum,
                    sanitizedRawLine: rawLine,
                    validationError: err,
                    isRepaired: isRep,
                    repairedTransactionId: repTx,
                    createdAt: created
                )
            )
        }
        return results
    }

    public func markImportJobIssueRepaired(issueId: UUID, tenantId: String, repairedTransactionId: UUID) throws {
        try executeParameterized(
            sql: "UPDATE import_job_issues SET is_repaired = 1, repaired_transaction_id = ? WHERE id = ? AND tenant_id = ?;",
            bind: { stmt in
                self.bindText(stmt, index: 1, value: repairedTransactionId.uuidString)
                self.bindText(stmt, index: 2, value: issueId.uuidString)
                self.bindText(stmt, index: 3, value: tenantId)
            }
        )
    }

    // MARK: - Module A: Workspace Ownership Verification, Sessions & Full Local Reset

    public func verifyWorkspaceOwnership(tenantId: String, userId: UUID) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM workspace_memberships WHERE tenant_id = ? AND user_id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else { return false }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: tenantId)
        bindText(prepared, index: 2, value: userId.uuidString)
        if sqlite3_step(prepared) == SQLITE_ROW {
            return sqlite3_column_int(prepared, 0) > 0
        }
        return false
    }

    public func upsertAppSession(_ session: AppSessionRecord) throws {
        try executeParameterized(
            sql: """
            INSERT OR REPLACE INTO app_sessions
            (session_id, user_id, tenant_id, auth_provider, created_at, last_active_at, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bind: { stmt in
                self.bindText(stmt, index: 1, value: session.sessionId)
                self.bindText(stmt, index: 2, value: session.userId)
                self.bindText(stmt, index: 3, value: session.tenantId)
                self.bindText(stmt, index: 4, value: session.authProvider)
                sqlite3_bind_int64(stmt, 5, Int64(session.createdAt.timeIntervalSince1970))
                sqlite3_bind_int64(stmt, 6, Int64(session.lastActiveAt.timeIntervalSince1970))
                sqlite3_bind_int(stmt, 7, session.isActive ? 1 : 0)
            }
        )
    }

    public func clearActiveSessions(tenantId: String) throws {
        try executeParameterized(
            sql: "UPDATE app_sessions SET is_active = 0 WHERE tenant_id = ?;",
            bind: { stmt in self.bindText(stmt, index: 1, value: tenantId) }
        )
    }

    public func countActiveSessions(tenantId: String) throws -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM app_sessions WHERE tenant_id = ? AND is_active = 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else { return 0 }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: tenantId)
        if sqlite3_step(prepared) == SQLITE_ROW {
            return Int(sqlite3_column_int(prepared, 0))
        }
        return 0
    }

    /// Completely wipes all local user and demo records from SQLite and re-seeds system categories cleanly.
    public func destroyAllLocalDataAndReinitialize() throws {
        try executeInTransaction {
            let allTables = [
                "savings_contributions",
                "import_job_issues",
                "transaction_subcategories",
                "transaction_categories",
                "app_sessions",
                "workspace_memberships",
                "user_preferences",
                "user_profiles",
                "financial_accounts",
                "transactions",
                "category_budgets",
                "fixed_commitments",
                "merchant_rules",
                "recurring_predictions",
                "savings_goals",
                "consent_records",
                "import_jobs",
                "notifications",
                "audit_events",
                "tenant_workspaces",
                "app_metadata"
            ]
            for table in allTables {
                try self.executeRawSQL("DELETE FROM \(table);")
            }
        }
        try seedSystemCategoriesIfNeeded()
    }

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    // MARK: - Low-Level SQLite Execution Helpers

    public func executeInTransaction(_ block: () throws -> Void) throws {
        try executeRawSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try block()
            try executeRawSQL("COMMIT TRANSACTION;")
        } catch {
            try? executeRawSQL("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    private func executeRawSQL(_ sql: String) throws {
        guard let db else { throw DatabaseError.openFailed("Database handle closed") }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "SQLite error \(rc)"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(msg)
        }
    }

    private func executeParameterized(sql: String, bind: (OpaquePointer) -> Void) throws {
        guard let db else { throw DatabaseError.openFailed("Database handle closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed(msg)
        }
        defer { sqlite3_finalize(prepared) }
        bind(prepared)
        let rc = sqlite3_step(prepared)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed(msg)
        }
    }

    private func queryPayloads<T: Decodable>(sql: String, tenantId: String) throws -> [T] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            return []
        }
        defer { sqlite3_finalize(prepared) }
        bindText(prepared, index: 1, value: tenantId)

        var results: [T] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            if let data = columnBlob(prepared, index: 0) {
                let decoded = try decoder.decode(T.self, from: data)
                results.append(decoded)
            }
        }
        return results
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { cStr in
            sqlite3_bind_text(stmt, index, cStr, -1, transient)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        bindText(stmt, index: index, value: value)
    }

    private func bindBlob(_ stmt: OpaquePointer?, index: Int32, data: Data) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(data.count), transient)
        }
    }

    private func columnBlob(_ stmt: OpaquePointer?, index: Int32) -> Data? {
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard length > 0, let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: ptr, count: length)
    }
}
