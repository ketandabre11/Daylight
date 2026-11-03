import SwiftUI

public enum ArchitectureDocumentationCatalog {
    // MARK: - Complete PostgreSQL 21-Table Relational DDL Migration (001_initial_schema.sql)

    public static let postgresMigrationSQL: String = """
    -- =============================================================================
    -- Daylight Money (Australian Personal Finance Platform)
    -- Migration: 001_initial_schema.sql
    -- Database: PostgreSQL 16+ (Strict Multi-Tenant Isolation, Integer Cents AUD)
    -- =============================================================================

    BEGIN;

    CREATE EXTENSION IF NOT EXISTS "pgcrypto";

    -- 1. users
    CREATE TABLE users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(255) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
        is_demo_user BOOLEAN NOT NULL DEFAULT FALSE,
        status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at TIMESTAMPTZ
    );

    -- 2. user_profiles
    CREATE TABLE user_profiles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        preferred_name VARCHAR(120) NOT NULL DEFAULT '',
        country_code CHAR(2) NOT NULL DEFAULT 'AU',
        currency_code CHAR(3) NOT NULL DEFAULT 'AUD',
        time_zone_id VARCHAR(64) NOT NULL DEFAULT 'Australia/Sydney',
        employment_type VARCHAR(48) NOT NULL DEFAULT 'salariedEmployee',
        pay_frequency VARCHAR(32) NOT NULL DEFAULT 'fortnightly',
        typical_take_home_pay_cents BIGINT NOT NULL DEFAULT 0 CHECK (typical_take_home_pay_cents >= 0),
        next_pay_date TIMESTAMPTZ NOT NULL,
        savings_target_cents BIGINT NOT NULL DEFAULT 0 CHECK (savings_target_cents >= 0),
        preferred_budgeting_method VARCHAR(48) NOT NULL DEFAULT 'payCycle',
        onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- 3. sessions
    CREATE TABLE sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        refresh_token_hash CHAR(64) NOT NULL UNIQUE,
        user_agent VARCHAR(512),
        ip_address INET,
        expires_at TIMESTAMPTZ NOT NULL,
        revoked_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_sessions_user_id ON sessions(user_id);

    -- 4. consent_records (CDR Open Banking & Privacy Act Consent Lifecycle)
    CREATE TABLE consent_records (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        institution_name VARCHAR(160) NOT NULL,
        provider_adapter_name VARCHAR(120) NOT NULL,
        scopes_granted JSONB NOT NULL DEFAULT '[]'::jsonb,
        is_sandbox_simulation BOOLEAN NOT NULL DEFAULT TRUE,
        granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ NOT NULL,
        revoked_at TIMESTAMPTZ,
        deletion_requested_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_consent_records_user_id ON consent_records(user_id);

    -- 5. financial_institutions
    CREATE TABLE financial_institutions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        code VARCHAR(64) NOT NULL UNIQUE,
        display_name VARCHAR(160) NOT NULL,
        country_code CHAR(2) NOT NULL DEFAULT 'AU',
        cdr_data_holder_brand_id VARCHAR(128),
        supports_osko_payid BOOLEAN NOT NULL DEFAULT TRUE,
        supports_bpay BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- 6. account_connections
    CREATE TABLE account_connections (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        institution_id UUID REFERENCES financial_institutions(id),
        consent_record_id UUID REFERENCES consent_records(id) ON DELETE SET NULL,
        connection_status VARCHAR(48) NOT NULL CHECK (connection_status IN ('manual', 'demoSynthetic', 'cdrSandboxActive', 'cdrRefreshFailed', 'disconnected')),
        last_successful_sync_at TIMESTAMPTZ,
        last_sync_error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_account_connections_user_id ON account_connections(user_id);

    -- 7. accounts
    CREATE TABLE accounts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        account_connection_id UUID REFERENCES account_connections(id) ON DELETE SET NULL,
        institution_name VARCHAR(160) NOT NULL,
        nickname VARCHAR(160) NOT NULL,
        account_type VARCHAR(48) NOT NULL,
        masked_account_number VARCHAR(32) NOT NULL,
        currency_code CHAR(3) NOT NULL DEFAULT 'AUD',
        available_balance_cents BIGINT NOT NULL DEFAULT 0,
        current_balance_cents BIGINT NOT NULL DEFAULT 0,
        balance_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        include_in_safe_to_spend BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at TIMESTAMPTZ
    );
    CREATE INDEX idx_accounts_user_id ON accounts(user_id);

    -- 8. account_balances
    CREATE TABLE account_balances (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        available_balance_cents BIGINT NOT NULL,
        current_balance_cents BIGINT NOT NULL,
        recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_account_balances_account_time ON account_balances(account_id, recorded_at DESC);

    -- 9. categories
    CREATE TABLE categories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        code VARCHAR(64) NOT NULL,
        display_name VARCHAR(120) NOT NULL,
        is_fixed_commitment BOOLEAN NOT NULL DEFAULT FALSE,
        is_income BOOLEAN NOT NULL DEFAULT FALSE,
        is_non_spending_transfer BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (user_id, code)
    );

    -- 10. merchants
    CREATE TABLE merchants (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        normalized_name VARCHAR(160) NOT NULL,
        default_category_code VARCHAR(64) NOT NULL,
        abn VARCHAR(16),
        payment_rail VARCHAR(64),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_merchants_user_name ON merchants(user_id, normalized_name);

    -- 11. transactions
    CREATE TABLE transactions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        source_transaction_id VARCHAR(160),
        reconciliation_fingerprint VARCHAR(255) NOT NULL,
        merchant_name VARCHAR(160) NOT NULL,
        raw_description TEXT NOT NULL,
        occurred_at TIMESTAMPTZ NOT NULL,
        amount_cents BIGINT NOT NULL CHECK (amount_cents >= 0),
        direction VARCHAR(16) NOT NULL CHECK (direction IN ('debit', 'credit')),
        category_code VARCHAR(64) NOT NULL,
        classification_confidence NUMERIC(4,3) NOT NULL DEFAULT 1.000,
        status VARCHAR(24) NOT NULL CHECK (status IN ('pending', 'posted', 'reversed')),
        kind VARCHAR(32) NOT NULL CHECK (kind IN ('expense', 'income', 'refund', 'reversal', 'ownAccountTransfer', 'creditCardPurchase', 'creditCardRepayment', 'bnplInstalment')),
        is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
        payment_rail VARCHAR(64),
        source VARCHAR(32) NOT NULL,
        user_note TEXT NOT NULL DEFAULT '',
        exclude_from_budget BOOLEAN NOT NULL DEFAULT FALSE,
        linked_original_transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
        calculation_version VARCHAR(32) NOT NULL DEFAULT 'au-v2.4.0',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at TIMESTAMPTZ,
        UNIQUE (user_id, account_id, reconciliation_fingerprint)
    );
    CREATE INDEX idx_transactions_user_occurred ON transactions(user_id, occurred_at DESC);
    CREATE INDEX idx_transactions_user_category ON transactions(user_id, category_code, occurred_at DESC);
    CREATE INDEX idx_transactions_user_account ON transactions(user_id, account_id, occurred_at DESC);

    -- 12. transaction_splits
    CREATE TABLE transaction_splits (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        category_code VARCHAR(64) NOT NULL,
        amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
        note VARCHAR(255) NOT NULL DEFAULT '',
        exclude_from_budget BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_transaction_splits_tx_id ON transaction_splits(transaction_id);

    -- 13. transaction_classification_events
    CREATE TABLE transaction_classification_events (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        previous_category_code VARCHAR(64),
        new_category_code VARCHAR(64) NOT NULL,
        classified_by VARCHAR(32) NOT NULL CHECK (classified_by IN ('rule_engine', 'user_manual', 'user_bulk', 'merchant_rule')),
        confidence NUMERIC(4,3) NOT NULL DEFAULT 1.000,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_tx_class_events_tx_id ON transaction_classification_events(transaction_id);

    -- 14. recurring_series
    CREATE TABLE recurring_series (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        merchant_name VARCHAR(160) NOT NULL,
        category_code VARCHAR(64) NOT NULL,
        expected_amount_cents BIGINT NOT NULL CHECK (expected_amount_cents >= 0),
        frequency VARCHAR(32) NOT NULL CHECK (frequency IN ('weekly', 'fortnightly', 'monthly', 'quarterly', 'annual')),
        confidence VARCHAR(32) NOT NULL,
        is_confirmed_by_user BOOLEAN NOT NULL DEFAULT FALSE,
        is_dismissed BOOLEAN NOT NULL DEFAULT FALSE,
        payment_rail VARCHAR(64),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_recurring_series_user_id ON recurring_series(user_id);

    -- 15. recurring_occurrences
    CREATE TABLE recurring_occurrences (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        recurring_series_id UUID NOT NULL REFERENCES recurring_series(id) ON DELETE CASCADE,
        transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
        expected_date TIMESTAMPTZ NOT NULL,
        amount_cents BIGINT NOT NULL,
        status VARCHAR(24) NOT NULL CHECK (status IN ('predicted', 'paid', 'skipped')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_recurring_occurrences_series_date ON recurring_occurrences(recurring_series_id, expected_date DESC);

    -- 16. pay_cycles
    CREATE TABLE pay_cycles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        frequency VARCHAR(32) NOT NULL,
        period_start TIMESTAMPTZ NOT NULL,
        period_end TIMESTAMPTZ NOT NULL,
        expected_take_home_cents BIGINT NOT NULL CHECK (expected_take_home_cents >= 0),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_pay_cycles_user_period ON pay_cycles(user_id, period_start DESC);

    -- 17. budgets
    CREATE TABLE budgets (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        budgeting_method VARCHAR(48) NOT NULL,
        period_start TIMESTAMPTZ NOT NULL,
        period_end TIMESTAMPTZ NOT NULL,
        total_flexible_budget_cents BIGINT NOT NULL,
        baseline_daily_allowance_cents BIGINT NOT NULL,
        calculation_version VARCHAR(32) NOT NULL DEFAULT 'au-v2.4.0',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_budgets_user_period ON budgets(user_id, period_start DESC);

    -- 18. budget_categories
    CREATE TABLE budget_categories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        budget_id UUID REFERENCES budgets(id) ON DELETE CASCADE,
        category_code VARCHAR(64) NOT NULL,
        limit_cents BIGINT NOT NULL CHECK (limit_cents >= 0),
        rollover_enabled BOOLEAN NOT NULL DEFAULT FALSE,
        rollover_balance_cents BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (user_id, category_code)
    );

    -- 19. savings_goals
    CREATE TABLE savings_goals (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        linked_account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
        name VARCHAR(160) NOT NULL,
        icon_name VARCHAR(64) NOT NULL,
        target_amount_cents BIGINT NOT NULL CHECK (target_amount_cents > 0),
        current_saved_cents BIGINT NOT NULL DEFAULT 0 CHECK (current_saved_cents >= 0),
        target_date TIMESTAMPTZ,
        assumptions_note TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at TIMESTAMPTZ
    );
    CREATE INDEX idx_savings_goals_user_id ON savings_goals(user_id);

    -- 20. notifications
    CREATE TABLE notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        title VARCHAR(200) NOT NULL,
        body TEXT NOT NULL,
        category_tag VARCHAR(64) NOT NULL,
        is_read BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_notifications_user_created ON notifications(user_id, created_at DESC);

    -- 21. import_jobs
    CREATE TABLE import_jobs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        target_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        idempotency_key VARCHAR(160) NOT NULL UNIQUE,
        file_name VARCHAR(255) NOT NULL,
        total_rows INT NOT NULL DEFAULT 0,
        imported_count INT NOT NULL DEFAULT 0,
        duplicate_skipped_count INT NOT NULL DEFAULT 0,
        rejected_count INT NOT NULL DEFAULT 0,
        status VARCHAR(48) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_import_jobs_user_created ON import_jobs(user_id, created_at DESC);

    -- 22. audit_events (Immutable Security & Financial Mutation Trail)
    CREATE TABLE audit_events (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        action VARCHAR(80) NOT NULL,
        entity_type VARCHAR(80) NOT NULL,
        entity_id VARCHAR(160) NOT NULL,
        summary TEXT NOT NULL,
        ip_address INET,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_audit_events_user_created ON audit_events(user_id, created_at DESC);

    COMMIT;
    """

    public static let requiredTableNames: [String] = [
        "users",
        "user_profiles",
        "sessions",
        "consent_records",
        "financial_institutions",
        "account_connections",
        "accounts",
        "account_balances",
        "categories",
        "merchants",
        "transactions",
        "transaction_splits",
        "transaction_classification_events",
        "recurring_series",
        "recurring_occurrences",
        "pay_cycles",
        "budgets",
        "budget_categories",
        "savings_goals",
        "notifications",
        "import_jobs",
        "audit_events"
    ]

    // MARK: - Australian Regulatory, Privacy & Security Compliance Checklist

    public static let australianComplianceChecklistMarkdown: String = """
    # Australian Regulatory, Privacy & Security Compliance Checklist

    ## 1. Privacy Act 1988 (Cth) & Australian Privacy Principles (APPs)
    - **APP 1 (Open & Transparent Management)**: Clear in-app disclosure explaining what personal and financial data is collected, how calculations work, and how to export or delete data.
    - **APP 3 & APP 11 (Data Minimisation & Security)**: Only fields required for personal cash-flow management are collected. Bank login passwords and Tax File Numbers (TFNs) are never collected or stored.
    - **APP 12 & APP 13 (Access & Correction)**: Users can inspect, edit, recategorise, or export 100% of their records in sanitized CSV and JSON formats at any time.
    - **Notifiable Data Breaches (NDB) Scheme Readiness**: Tamper-evident `audit_events` logging, strict tenant isolation (`tenantId` ownership checks on every query/mutation), and zero sensitive amounts in system logs.

    ## 2. Consumer Data Right (CDR / Open Banking) Governance
    - **Honest Accreditation Posture**: Live CDR data sharing requires ACCC Data Recipient accreditation or an approved CDR intermediary. This application implements a clean `AccountConnectionAdapter` boundary with `ConsentRecord` tracking (`scopesGranted`, `grantedAt`, `expiresAt`, `revokedAt`) and explicitly labels simulated connections as **Sandbox / Synthetic Demo**.
    - **Consent Revocation & Deletion**: Disconnecting an account immediately revokes the associated `ConsentRecord` and halts data collection.

    ## 3. Australian Financial Services (ASIC) & Australian Consumer Law (ACL)
    - **General Information Boundary**: All insights, daily allowances, and savings projections are factual mathematical calculations based on user-supplied or imported figures, not personal financial product advice under the *Corporations Act 2001 (Cth)*.
    - **Accurate Claims (ACL)**: Bank account balances (`Available Balance` vs `Current Ledger Balance`) are visually and mathematically separated from budgeting figures (`Safe-to-Spend Today` and `Remaining Flexible Budget`).

    ## 4. Threat Model & OWASP Mitigations
    - **Broken Object Level Authorization (BOLA / IDOR)**: Prevented via mandatory `verifyOwnership(entityTenantId:)` checks on every domain mutation and isolated tenant snapshots (`tenant_demo_au` vs `tenant_personal_au`).
    - **Floating-Point Rounding Drift**: Prevented by storing and computing all AUD monetary amounts in 64-bit integer cents (`MoneyCents = Int64`).
    - **CSV Formula Injection**: Exported CSV fields starting with `=`, `+`, `-`, `@`, `\\t`, or `\\r` are prefixed with a leading single quote (`'`) and RFC-4180 escaped.
    - **Duplicate Statement Replay**: Prevented via deterministic `reconciliationFingerprint` hashing combined with per-batch sequence indexing and `idempotencyKey` enforcement.
    """

    // MARK: - Reference API & Deployment Runbook

    public static let apiAndOperationsGuideMarkdown: String = """
    # API Contract, Deployment & Disaster Recovery Runbook

    ## 1. Versioned REST API Endpoints (`/api/v1`)
    - `POST /api/v1/auth/session` — Argon2id authentication + short-lived access token + rotating refresh token
    - `GET  /api/v1/dashboard/allowance` — Deterministic daily safe-to-spend summary (`calculationVersion: au-v2.4.0`)
    - `GET  /api/v1/accounts` & `POST /api/v1/accounts` — Account balances & CDR consent status
    - `GET  /api/v1/transactions` & `PATCH /api/v1/transactions/{id}` — Paginated transaction explorer, splits & bulk categorisation
    - `POST /api/v1/imports/csv` — Idempotent (`Idempotency-Key` header) Australian bank statement import
    - `GET  /api/v1/budgets` & `PUT /api/v1/budgets/categories` — All 6 budgeting methods & category limits
    - `GET  /api/v1/recurring` & `POST /api/v1/recurring/{id}/confirm` — Recurring bill predictions
    - `GET  /api/v1/savings-goals` & `POST /api/v1/savings-goals/{id}/contributions` — Savings goals
    - `GET  /api/v1/exports/csv` & `GET /api/v1/exports/json` — Formula-sanitized data portability exports
    - `DELETE /api/v1/workspace` — Immediate account and personal data erasure

    ## 2. Backup, Restore & Disaster Recovery
    - **Point-in-Time Recovery (PITR)**: PostgreSQL WAL archiving with 35-day encrypted retention in `ap-southeast-2` (Sydney).
    - **RPO / RTO Targets**: RPO < 5 minutes (streaming WAL); RTO < 30 minutes via automated Terraform/Container promotion.
    - **Verification Drill**: Monthly automated restore into an isolated staging VPC running the reconciliation integrity test suite.
    """
}

// MARK: - In-App Architecture, SQL & Compliance Inspector Sheet

public struct ArchitectureAndComplianceInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                    PrivacySecurityHero()

                    PrivacySecurityInformationCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Your workspace",
                        message: "Your profile, accounts, budgets, and transactions are used to provide the features you choose in Daylight."
                    )

                    PrivacySecurityInformationCard(
                        icon: "square.and.arrow.up",
                        title: "Exports stay in your control",
                        message: "When you export data, you choose where to save it. Review export files carefully, as they can contain sensitive financial information."
                    )

                    PrivacySecurityInformationCard(
                        icon: "calendar.badge.clock",
                        title: "Choose what to export",
                        message: "CSV exports include only the period you select. A full workspace archive can include your broader workspace information, so review it before sharing."
                    )

                    PrivacySecurityInformationCard(
                        icon: "trash",
                        title: "You can delete your data",
                        message: "The Delete Workspace option in Settings permanently removes the current workspace data after confirmation."
                    )

                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xs) {
                        Label("Need help with privacy?", systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("Contact (daylight.support@gmail.com) if you have a question about your data or privacy settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DaylightTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                            .fill(DaylightTheme.secondarySurface(for: colorScheme))
                    )
                }
                .padding(DaylightTheme.Spacing.md)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Privacy & Security")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PrivacySecurityHero: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: DaylightTheme.Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(DaylightTheme.accent)
                .frame(width: 48, height: 48)
                .background(Circle().fill(DaylightTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xxs) {
                Text("Your data, explained simply")
                    .font(.title3.weight(.semibold))
                Text("Understand what is included in your workspace and make informed choices when exporting or deleting it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DaylightTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                .fill(DaylightTheme.sageSurface(for: colorScheme))
        )
    }
}

private struct PrivacySecurityInformationCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DaylightTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DaylightTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm, style: .continuous)
                        .fill(DaylightTheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DaylightTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                .fill(DaylightTheme.surface(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                .strokeBorder(DaylightTheme.border(for: colorScheme), lineWidth: 1)
        )
    }
}
