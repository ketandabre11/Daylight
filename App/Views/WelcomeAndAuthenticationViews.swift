import SwiftUI

// MARK: - Root Signed-Out Container (Welcome / Register / Login)

public struct WelcomeAndAuthContainerView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            DaylightTheme.background(for: colorScheme)
                .ignoresSafeArea()

            Group {
                switch store.authNavigationRoute {
                case .welcome:
                    DaylightWelcomeView(store: store)
                        .transition(.opacity)
                case .register:
                    DaylightRegistrationView(store: store)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .login:
                    DaylightLoginView(store: store)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: store.authNavigationRoute)
        }
    }
}

// MARK: - 3. Welcome Screen

public struct DaylightWelcomeView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: DaylightStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DaylightTheme.Spacing.xl) {
                Spacer(minLength: DaylightTheme.Spacing.md)

                // Branding & Hero
                VStack(spacing: DaylightTheme.Spacing.md) {
                    DaylightBrandMarkView(size: 76)

                    Text("Daylight Money")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.forestGreen)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text("A clearer view of your money.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Track everyday spending, manage pay-cycle budgets, and build lasting savings with calm, transparent financial clarity designed for Australians.")
                        .font(.body)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DaylightTheme.Spacing.sm)
                }

                // Value Proposition Cards (No fabricated account balances or fake transactions)
                VStack(spacing: DaylightTheme.Spacing.sm) {
                    welcomeFeatureRow(
                        icon: "sun.max.fill",
                        title: "Safe-to-Spend Clarity",
                        description: "Know what you can comfortably spend each day after bills, category budgets, and savings targets."
                    )
                    welcomeFeatureRow(
                        icon: "chart.pie.fill",
                        title: "Budgets & Custom Categories",
                        description: "Organise spending across Australian essentials and custom categories tailored to your household."
                    )
                    welcomeFeatureRow(
                        icon: "target",
                        title: "Dedicated Savings Goals",
                        description: "Record contributions and track progress toward your emergency fund, holiday, or home deposit."
                    )
                }

                if let errorMsg = store.authErrorMessage {
                    DaylightCard(padding: DaylightTheme.Spacing.sm) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DaylightTheme.cautionRed)
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }

                // Primary & Secondary Actions
                VStack(spacing: DaylightTheme.Spacing.sm) {
                    Button {
                        store.authErrorMessage = nil
                        store.authNavigationRoute = .register
                    } label: {
                        Text("Create your account")
                    }
                    .buttonStyle(DaylightPrimaryButtonStyle())
                    .accessibilityIdentifier("welcome_create_account_button")
                    .accessibilityHint("Opens the account registration form")

                    Button {
                        store.authErrorMessage = nil
                        store.authNavigationRoute = .login
                    } label: {
                        Text("Log in")
                    }
                    .buttonStyle(DaylightSecondaryButtonStyle())
                    .accessibilityIdentifier("welcome_login_button")
                    .accessibilityHint("Opens the login screen for existing accounts")

                    Button {
                        store.enterSyntheticDemoWorkspace()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Explore Synthetic Australian Demo")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DaylightTheme.forestGreen)
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("welcome_explore_demo_button")
                }

                // Brief Privacy Statement
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption)
                            .foregroundStyle(DaylightTheme.forestGreen)
                        Text("Private by Design")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                    }
                    Text("Your financial records are stored in an isolated per-account workspace and protected by Apple Keychain authentication. Daylight Money never sells your data or stores banking passwords.")
                        .font(.caption2)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DaylightTheme.Spacing.sm)
                .padding(.bottom, DaylightTheme.Spacing.lg)
            }
            .padding(.horizontal, DaylightTheme.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func welcomeFeatureRow(icon: String, title: String, description: String) -> some View {
        DaylightCard(padding: DaylightTheme.Spacing.md) {
            HStack(alignment: .top, spacing: DaylightTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(DaylightTheme.forestGreen)
                    .frame(width: 38, height: 38)
                    .background(DaylightTheme.sageSurface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 4. Registration Screen

public struct DaylightRegistrationView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var hasInteractedWithForm: Bool = false

    public init(store: DaylightStore) {
        self.store = store
    }

    private var validation: AuthFormValidationResult {
        AuthFormValidator.validateRegistration(
            fullName: fullName,
            email: email,
            password: password,
            confirmPassword: confirmPassword
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                // Back button to Welcome
                Button {
                    store.authErrorMessage = nil
                    store.authNavigationRoute = .welcome
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Welcome")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DaylightTheme.forestGreen)
                }
                .padding(.top, DaylightTheme.Spacing.sm)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create your account")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                        .accessibilityAddTraits(.isHeader)

                    Text("Start with a clean personal workspace tailored to your Australian pay cycle and categories.")
                        .font(.subheadline)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                }

                if let errorMsg = store.authErrorMessage {
                    DaylightCard(padding: DaylightTheme.Spacing.sm) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(DaylightTheme.cautionRed)
                            Text(errorMsg)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DaylightTheme.cautionRed)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("Registration error: \(errorMsg)")
                }

                // Form Fields Card
                DaylightCard(padding: DaylightTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                        // Full Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Taylor Morgan", text: $fullName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .accessibilityIdentifier("register_full_name_field")
                            if hasInteractedWithForm || !fullName.isEmpty,
                               let nameErr = validation.fullNameError {
                                Text(nameErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            }
                        }

                        // Email Address
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email address")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("name@example.com.au", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("register_email_field")
                            if hasInteractedWithForm || !email.isEmpty,
                               let emailErr = validation.emailError {
                                Text(emailErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            }
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Password")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Label(
                                        showPassword ? "Hide" : "Show",
                                        systemImage: showPassword ? "eye.slash" : "eye"
                                    )
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DaylightTheme.forestGreen)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }

                            Group {
                                if showPassword {
                                    TextField("At least 8 characters", text: $password)
                                } else {
                                    SecureField("At least 8 characters", text: $password)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("register_password_field")

                            if hasInteractedWithForm || !password.isEmpty,
                               let pwErr = validation.passwordError {
                                Text(pwErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            } else {
                                Text("Use 8+ characters with at least one letter and one number or symbol.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Confirm Password
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Confirm password")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    showConfirmPassword.toggle()
                                } label: {
                                    Label(
                                        showConfirmPassword ? "Hide" : "Show",
                                        systemImage: showConfirmPassword ? "eye.slash" : "eye"
                                    )
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DaylightTheme.forestGreen)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showConfirmPassword ? "Hide confirm password" : "Show confirm password")
                            }

                            Group {
                                if showConfirmPassword {
                                    TextField("Re-enter password", text: $confirmPassword)
                                } else {
                                    SecureField("Re-enter password", text: $confirmPassword)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("register_confirm_password_field")

                            if hasInteractedWithForm || !confirmPassword.isEmpty,
                               let confirmErr = validation.confirmPasswordError {
                                Text(confirmErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            }
                        }
                    }
                }

                // Create Account Action
                Button {
                    hasInteractedWithForm = true
                    guard validation.isValid, !store.isAuthSubmitting else { return }
                    Task {
                        try? await store.registerAccount(
                            fullName: fullName,
                            email: email,
                            password: password,
                            confirmPassword: confirmPassword
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isAuthSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(store.isAuthSubmitting ? "Creating your workspace..." : "Create Account")
                    }
                }
                .buttonStyle(DaylightPrimaryButtonStyle())
                .disabled(!validation.isValid || store.isAuthSubmitting)
                .accessibilityIdentifier("register_submit_button")

                // Link to Login Screen
                HStack {
                    Spacer()
                    Button {
                        store.authErrorMessage = nil
                        store.authNavigationRoute = .login
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(.secondary)
                            Text("Log in")
                                .fontWeight(.semibold)
                                .foregroundStyle(DaylightTheme.forestGreen)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("register_switch_to_login_button")
                    Spacer()
                }
                .padding(.bottom, DaylightTheme.Spacing.lg)
            }
            .padding(.horizontal, DaylightTheme.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 5. Login Screen

public struct DaylightLoginView: View {
    @Bindable var store: DaylightStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var hasInteractedWithForm: Bool = false
    @State private var showingResetNotice: Bool = false

    public init(store: DaylightStore) {
        self.store = store
    }

    private var validation: AuthFormValidationResult {
        AuthFormValidator.validateLogin(email: email, password: password)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DaylightTheme.Spacing.lg) {
                // Back button to Welcome
                Button {
                    store.authErrorMessage = nil
                    store.authNavigationRoute = .welcome
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Welcome")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DaylightTheme.forestGreen)
                }
                .padding(.top, DaylightTheme.Spacing.sm)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome back")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                        .accessibilityAddTraits(.isHeader)

                    Text("Log in to access your personal Daylight Money workspace.")
                        .font(.subheadline)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                }

                if let errorMsg = store.authErrorMessage {
                    DaylightCard(padding: DaylightTheme.Spacing.sm) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(DaylightTheme.cautionRed)
                            Text(errorMsg)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DaylightTheme.cautionRed)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("Login error: \(errorMsg)")
                }

                // Login Form Card
                DaylightCard(padding: DaylightTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DaylightTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email address")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("name@example.com.au", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("login_email_field")
                            if hasInteractedWithForm || !email.isEmpty,
                               let emailErr = validation.emailError {
                                Text(emailErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Password")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Label(
                                        showPassword ? "Hide" : "Show",
                                        systemImage: showPassword ? "eye.slash" : "eye"
                                    )
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DaylightTheme.forestGreen)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }

                            Group {
                                if showPassword {
                                    TextField("Enter your password", text: $password)
                                } else {
                                    SecureField("Enter your password", text: $password)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .accessibilityIdentifier("login_password_field")

                            if hasInteractedWithForm,
                               let pwErr = validation.passwordError {
                                Text(pwErr)
                                    .font(.caption2)
                                    .foregroundStyle(DaylightTheme.cautionRed)
                            }
                        }

                        if store.authService.supportsForgotPassword {
                            HStack {
                                Spacer()
                                Button("Forgot password?") {
                                    showingResetNotice = true
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DaylightTheme.forestGreen)
                            }
                        }
                    }
                }

                // Login Button
                Button {
                    hasInteractedWithForm = true
                    guard validation.isValid, !store.isAuthSubmitting else { return }
                    Task {
                        try? await store.loginAccount(email: email, password: password)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isAuthSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(store.isAuthSubmitting ? "Signing in..." : "Log in")
                    }
                }
                .buttonStyle(DaylightPrimaryButtonStyle())
                .disabled(!validation.isValid || store.isAuthSubmitting)
                .accessibilityIdentifier("login_submit_button")

                // Link to Registration Screen
                HStack {
                    Spacer()
                    Button {
                        store.authErrorMessage = nil
                        store.authNavigationRoute = .register
                    } label: {
                        HStack(spacing: 4) {
                            Text("New to Daylight Money?")
                                .foregroundStyle(.secondary)
                            Text("Create your account")
                                .fontWeight(.semibold)
                                .foregroundStyle(DaylightTheme.forestGreen)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("login_switch_to_register_button")
                    Spacer()
                }

                // Provider status disclosure
                DaylightCard(padding: DaylightTheme.Spacing.sm) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundStyle(DaylightTheme.sageAccent)
                        Text(store.authService.backendConfigurationStatusSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, DaylightTheme.Spacing.lg)
            }
            .padding(.horizontal, DaylightTheme.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .alert("Password Reset", isPresented: $showingResetNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("If an account matches this email address, password reset instructions have been requested via the configured identity endpoint.")
        }
    }
}

// MARK: - 9. Categories Management Sheet (System & Custom Categories CRUD)

public struct CategoriesManagementSheet: View {
    @Bindable var store: DaylightStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = "tag.fill"
    @State private var newCategoryType: TransactionCategoryType = .expense
    @State private var includeArchived: Bool = false

    @State private var editingCategory: TransactionCategoryRecord? = nil
    @State private var editedName: String = ""
    @State private var editedIcon: String = "tag.fill"

    @State private var categoryPendingDelete: TransactionCategoryRecord? = nil
    @State private var reassignmentCategory: AustralianCategory = .cashAndUnclassified
    @State private var errorMessage: String? = nil

    private let availableIcons = [
        "tag.fill", "pawprint.fill", "leaf.fill", "book.fill",
        "paintbrush.fill", "music.note", "gift.fill", "wrench.and.screwdriver.fill",
        "bicycle", "cup.and.saucer.fill", "camera.fill", "graduationcap.fill"
    ]

    public init(store: DaylightStore) {
        self.store = store
    }

    private var customCategories: [TransactionCategoryRecord] {
        store.workspaceCategories
            .filter { !$0.isSystemDefault && (includeArchived || !$0.isArchived) }
            .sorted { lhs, rhs in
                if lhs.displayOrder == rhs.displayOrder {
                    return lhs.name < rhs.name
                }
                return lhs.displayOrder < rhs.displayOrder
            }
    }

    private var systemCategories: [TransactionCategoryRecord] {
        store.workspaceCategories
            .filter { $0.isSystemDefault }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    public var body: some View {
        NavigationStack {
            List {
                errorBannerSection
                createCustomCategorySection
                workspaceCustomCategoriesSection
                systemCategoriesSection
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.refreshWorkspaceCategories(includeArchived: true)
            }
            .sheet(item: $editingCategory) { cat in
                editCategoryModal(cat)
            }
            .alert(
                "Category In Use",
                isPresented: Binding(
                    get: { categoryPendingDelete != nil },
                    set: { if !$0 { categoryPendingDelete = nil } }
                ),
                presenting: categoryPendingDelete
            ) { cat in
                Button("Reassign to \(reassignmentCategory.displayName) & Delete", role: .destructive) {
                    try? store.deleteCustomCategory(
                        categoryId: cat.id,
                        reassignToCategory: reassignmentCategory
                    )
                    categoryPendingDelete = nil
                }
                Button("Archive Instead") {
                    var copy = cat
                    copy.isArchived = true
                    try? store.updateCustomCategory(copy)
                    categoryPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    categoryPendingDelete = nil
                }
            } message: { cat in
                Text("'\(cat.name)' is referenced by existing transactions. To prevent broken records, you can reassign those transactions to \(reassignmentCategory.displayName) before deleting, or archive the category instead.")
            }
        }
    }

    @ViewBuilder
    private var errorBannerSection: some View {
        if let errorMessage {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DaylightTheme.cautionRed)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(DaylightTheme.cautionRed)
                }
            }
        }
    }

    private var createCustomCategorySection: some View {
        Section("Create Custom Category") {
            TextField("Category name (e.g. Pet Care, Books, Side Hustle)", text: $newCategoryName)
                .accessibilityIdentifier("custom_category_name_field")

            Picker("Category Type", selection: $newCategoryType) {
                Text("Expense").tag(TransactionCategoryType.expense)
                Text("Income").tag(TransactionCategoryType.income)
                Text("Transfer").tag(TransactionCategoryType.transfer)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newCategoryIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.subheadline)
                                .frame(width: 34, height: 34)
                                .background(newCategoryIcon == icon ? DaylightTheme.forestGreen : Color.secondary.opacity(0.14))
                                .foregroundStyle(newCategoryIcon == icon ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                createCategory()
            } label: {
                Label("Add Custom Category", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DaylightTheme.forestGreen)
            }
            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("add_custom_category_button")
        }
    }

    private var workspaceCustomCategoriesSection: some View {
        Section {
            Toggle("Show Archived Categories", isOn: $includeArchived)
                .font(.caption)

            if customCategories.isEmpty {
                Text("No custom categories yet. Create one above to tailor Daylight Money to your household.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customCategories) { cat in
                    customCategoryRow(cat)
                }
            }
        } header: {
            Text("Your Custom Categories (\(customCategories.count))")
        }
    }

    private func customCategoryRow(_ cat: TransactionCategoryRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cat.iconName)
                .foregroundStyle(DaylightTheme.forestGreen)
                .frame(width: 28, height: 28)
                .background(DaylightTheme.forestGreen.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cat.name)
                        .font(.subheadline.weight(.semibold))
                    if cat.isArchived {
                        DaylightBadge("Archived", icon: "archivebox", tone: .neutral)
                    }
                }
                Text(cat.categoryType.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                try? store.moveCustomCategory(categoryId: cat.id, direction: -1)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move \(cat.name) up")

            Button {
                try? store.moveCustomCategory(categoryId: cat.id, direction: 1)
            } label: {
                Image(systemName: "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move \(cat.name) down")

            Menu {
                Button {
                    editingCategory = cat
                    editedName = cat.name
                    editedIcon = cat.iconName
                } label: {
                    Label("Rename / Edit Icon", systemImage: "pencil")
                }

                Button {
                    var updated = cat
                    updated.isArchived.toggle()
                    try? store.updateCustomCategory(updated)
                } label: {
                    Label(
                        cat.isArchived ? "Unarchive Category" : "Archive Category",
                        systemImage: cat.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }

                Button(role: .destructive) {
                    attemptDeleteCategory(cat)
                } label: {
                    Label("Delete Category", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var systemCategoriesSection: some View {
        Section("System Australian Categories (\(systemCategories.count))") {
            ForEach(systemCategories) { sys in
                HStack(spacing: 12) {
                    Image(systemName: sys.iconName)
                        .foregroundStyle(DaylightTheme.sageAccent)
                        .frame(width: 28, height: 28)
                        .background(DaylightTheme.sageAccent.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sys.name)
                            .font(.subheadline)
                        Text(sys.categoryType.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    DaylightBadge("System", icon: "checkmark.seal", tone: .neutral)
                }
            }
        }
    }

    private func editCategoryModal(_ cat: TransactionCategoryRecord) -> some View {
        NavigationStack {
            Form {
                Section("Rename Category") {
                    TextField("Category Name", text: $editedName)
                }
                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    editedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .frame(width: 34, height: 34)
                                        .background(editedIcon == icon ? DaylightTheme.forestGreen : Color.secondary.opacity(0.15))
                                        .foregroundStyle(editedIcon == icon ? .white : .primary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingCategory = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = cat
                        updated.name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.iconName = editedIcon
                        do {
                            try store.updateCustomCategory(updated)
                            editingCategory = nil
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createCategory() {
        errorMessage = nil
        do {
            _ = try store.createCustomCategory(
                name: newCategoryName,
                iconName: newCategoryIcon,
                categoryType: newCategoryType,
                displayOrder: 150 + (customCategories.count * 5)
            )
            newCategoryName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attemptDeleteCategory(_ cat: TransactionCategoryRecord) {
        errorMessage = nil
        do {
            try store.deleteCustomCategory(categoryId: cat.id, reassignToCategory: nil)
        } catch {
            // Category is referenced by existing transactions; prompt for safe reassignment or archiving
            categoryPendingDelete = cat
        }
    }
}
