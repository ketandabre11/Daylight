import CryptoKit
import Foundation
import Security

// MARK: - Authentication Navigation & Session Models

public enum AuthenticationRoute: String, Codable, Equatable, Hashable, Sendable {
    case welcome
    case register
    case login
}

public enum AuthenticationProviderMode: String, Codable, Equatable, Sendable {
    case remoteBackendAPI = "remote_backend_api"
    case developmentKeychain = "development_keychain"
    case testInMemoryMock = "test_in_memory_mock"

    public var displayName: String {
        switch self {
        case .remoteBackendAPI:
            return "Online Authentication API"
        case .developmentKeychain:
            return "On-Device Keychain Identity (Development Mode)"
        case .testInMemoryMock:
            return "In-Memory Test Identity Provider"
        }
    }
}

public struct AuthenticatedSession: Codable, Equatable, Sendable {
    public var sessionId: String
    public var userId: String
    public var email: String
    public var fullName: String
    /// Server/identity-bound workspace tenant identifier (`tenant_user_<userId>`).
    public var workspaceTenantId: String
    public var issuedAt: Date
    public var expiresAt: Date
    public var providerMode: AuthenticationProviderMode

    public init(
        sessionId: String,
        userId: String,
        email: String,
        fullName: String,
        workspaceTenantId: String,
        issuedAt: Date,
        expiresAt: Date,
        providerMode: AuthenticationProviderMode
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.email = email
        self.fullName = fullName
        self.workspaceTenantId = workspaceTenantId
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.providerMode = providerMode
    }

    public func isExpired(at referenceDate: Date = Date()) -> Bool {
        referenceDate >= expiresAt
    }
}

public enum AuthenticationState: Equatable, Sendable {
    case signedOut
    case authenticating
    case authenticated(AuthenticatedSession)

    public var currentSession: AuthenticatedSession? {
        if case .authenticated(let session) = self {
            return session
        }
        return nil
    }

    public var isSignedIn: Bool {
        currentSession != nil
    }
}

// MARK: - Authentication Errors (Anti-Enumeration & Clear User Feedback)

public enum DaylightAuthenticationError: LocalizedError, Equatable, Sendable {
    case invalidInput(String)
    /// Uniform error used for unknown email OR wrong password to prevent account enumeration.
    case invalidCredentials
    case registrationUnavailable
    case sessionExpired
    case networkFailure(String)
    case backendConfigurationRequired
    case remoteBackendUnavailable
    case unauthorizedWorkspaceAccess

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):
            return msg
        case .invalidCredentials:
            return "Invalid email address or password. Please check your credentials and try again."
        case .registrationUnavailable:
            return "Unable to create an account with these details. If you already have an account, please log in instead."
        case .sessionExpired:
            return "Your session has expired. Please log in again to access your workspace."
        case .networkFailure(let detail):
            return "Unable to reach the authentication service (\(detail)). Please check your connection and try again."
        case .backendConfigurationRequired:
            return "Production authentication backend is not configured. Set DAYLIGHT_AUTH_API_BASE_URL in environment configuration."
        case .remoteBackendUnavailable:
            return "Online authentication is configured but unavailable in this build. Remove DAYLIGHT_AUTH_API_BASE_URL or provide the supported authentication client."
        case .unauthorizedWorkspaceAccess:
            return "Your account is not authorised to access the requested financial workspace."
        }
    }
}

// MARK: - Form Validation Policy

public struct AuthFormValidationResult: Equatable, Sendable {
    public var fullNameError: String?
    public var emailError: String?
    public var passwordError: String?
    public var confirmPasswordError: String?

    public var isValid: Bool {
        fullNameError == nil && emailError == nil && passwordError == nil && confirmPasswordError == nil
    }

    public var firstErrorMessage: String? {
        fullNameError ?? emailError ?? passwordError ?? confirmPasswordError
    }
}

public enum AuthFormValidator {
    public static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValidEmailSyntax(_ email: String) -> Bool {
        let trimmed = normalizeEmail(email)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, domain.count >= 3, domain.contains(".") else { return false }
        let domainParts = domain.split(separator: ".", omittingEmptySubsequences: false)
        return domainParts.allSatisfy { !$0.isEmpty } && (domainParts.last?.count ?? 0) >= 2
    }

    /// Password policy: minimum 8 characters, at least 1 letter and at least 1 number or symbol.
    public static func validatePasswordPolicy(_ password: String) -> String? {
        guard password.count >= 8 else {
            return "Password must be at least 8 characters long."
        }
        let hasLetter = password.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasDigitOrSymbol = password.unicodeScalars.contains {
            CharacterSet.decimalDigits.contains($0) || CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
        guard hasLetter && hasDigitOrSymbol else {
            return "Password must include at least one letter and one number or symbol."
        }
        return nil
    }

    public static func validateRegistration(
        fullName: String,
        email: String,
        password: String,
        confirmPassword: String
    ) -> AuthFormValidationResult {
        var result = AuthFormValidationResult()
        let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.count < 2 {
            result.fullNameError = "Please enter your full name."
        }
        if !isValidEmailSyntax(email) {
            result.emailError = "Please enter a valid email address (e.g. alex@example.com.au)."
        }
        if let pwErr = validatePasswordPolicy(password) {
            result.passwordError = pwErr
        }
        if confirmPassword.isEmpty {
            result.confirmPasswordError = "Please confirm your password."
        } else if password != confirmPassword {
            result.confirmPasswordError = "Passwords do not match."
        }
        return result
    }

    public static func validateLogin(
        email: String,
        password: String
    ) -> AuthFormValidationResult {
        var result = AuthFormValidationResult()
        if !isValidEmailSyntax(email) {
            result.emailError = "Please enter a valid email address."
        }
        if password.isEmpty {
            result.passwordError = "Please enter your password."
        }
        return result
    }
}

// MARK: - Authentication Service Protocol

public protocol DaylightAuthenticationServiceProtocol: Sendable {
    var providerMode: AuthenticationProviderMode { get }
    var isOnlineBackendConfigured: Bool { get }
    var supportsForgotPassword: Bool { get }
    var backendConfigurationStatusSummary: String { get }

    func restoreSession(now: Date) async throws -> AuthenticatedSession?
    func register(fullName: String, email: String, password: String, now: Date) async throws -> AuthenticatedSession
    func login(email: String, password: String, now: Date) async throws -> AuthenticatedSession
    func updateAuthenticatedUserName(_ newFullName: String)
    func logout(session: AuthenticatedSession?) async
}

// MARK: - Keychain & In-Memory Credential Verifier Vault (No Plaintext Passwords)

private struct StoredAccountCredentialRecord: Codable, Sendable {
    var userId: String
    var email: String
    var fullName: String
    var workspaceTenantId: String
    var saltHex: String
    var verifierHex: String
    var verifierVersion: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case userId, email, fullName, workspaceTenantId, saltHex, verifierHex, verifierVersion, createdAt
    }

    init(
        userId: String,
        email: String,
        fullName: String,
        workspaceTenantId: String,
        saltHex: String,
        verifierHex: String,
        verifierVersion: Int = 2,
        createdAt: Date
    ) {
        self.userId = userId
        self.email = email
        self.fullName = fullName
        self.workspaceTenantId = workspaceTenantId
        self.saltHex = saltHex
        self.verifierHex = verifierHex
        self.verifierVersion = verifierVersion
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        email = try container.decode(String.self, forKey: .email)
        fullName = try container.decode(String.self, forKey: .fullName)
        workspaceTenantId = try container.decode(String.self, forKey: .workspaceTenantId)
        saltHex = try container.decode(String.self, forKey: .saltHex)
        verifierHex = try container.decode(String.self, forKey: .verifierHex)
        verifierVersion = try container.decodeIfPresent(Int.self, forKey: .verifierVersion) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// Thread-safe Keychain / in-memory credential and session token store.
/// Never stores plaintext passwords or logs sensitive values.
public final class DaylightSecureAuthVault: @unchecked Sendable {
    private let lock = NSLock()
    private let useInMemoryStorage: Bool
    private let serviceIdentifier: String
    private var memoryStore: [String: Data] = [:]

    public init(
        useInMemoryStorage: Bool = false,
        serviceIdentifier: String = "au.com.daylightmoney.auth.v1"
    ) {
        self.useInMemoryStorage = useInMemoryStorage
        self.serviceIdentifier = serviceIdentifier
    }

    public func writeData(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if useInMemoryStorage {
            memoryStore[key] = data
            return
        }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            memoryStore[key] = data
        }
    }

    public func readData(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if useInMemoryStorage {
            return memoryStore[key]
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return data
        }
        return memoryStore[key]
    }

    public func deleteData(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        memoryStore.removeValue(forKey: key)
        guard !useInMemoryStorage else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func derivePasswordVerifier(password: String, saltHex: String) -> String {
        let passwordData = Data(password.utf8)
        let saltData = Data(saltHex.utf8)
        let iterations: UInt32 = 120_000
        var message = saltData
        message.append(contentsOf: [0, 0, 0, 1])
        var u = Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: passwordData)))
        var derived = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: passwordData)))
                for index in derived.indices {
                    derived[index] ^= u[index]
                }
            }
        }
        return "pbkdf2-sha256$\(iterations)$\(derived.map { String(format: "%02x", $0) }.joined())"
    }

    fileprivate static func deriveLegacyPasswordVerifier(password: String, saltHex: String) -> String {
        var digestData = Data((saltHex + ":" + password).utf8)
        for round in 0..<2_048 {
            var roundInput = digestData
            roundInput.append(contentsOf: withUnsafeBytes(of: UInt16(round).bigEndian, Array.init))
            digestData = Data(SHA256.hash(data: roundInput))
        }
        return digestData.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Keychain / Test Mock Authentication Service Implementation

public final class DaylightAuthenticationService: DaylightAuthenticationServiceProtocol, @unchecked Sendable {
    public let providerMode: AuthenticationProviderMode
    public let isOnlineBackendConfigured: Bool
    public let supportsForgotPassword: Bool
    public let vault: DaylightSecureAuthVault
    private let sessionDurationSeconds: TimeInterval

    public static let accountsRegistryKey = "registered_accounts_v1"
    public static let activeSessionKey = "active_authenticated_session_v1"

    public init(
        useInMemoryMock: Bool = false,
        sessionDurationSeconds: TimeInterval = 86_400 * 14,
        serviceIdentifier: String = "au.com.daylightmoney.auth.v1"
    ) {
        let configuredBaseURL = ProcessInfo.processInfo.environment["DAYLIGHT_AUTH_API_BASE_URL"] ?? ""
        self.isOnlineBackendConfigured = !configuredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.supportsForgotPassword = isOnlineBackendConfigured
        self.providerMode = useInMemoryMock ? .testInMemoryMock : (isOnlineBackendConfigured ? .remoteBackendAPI : .developmentKeychain)
        self.vault = DaylightSecureAuthVault(
            useInMemoryStorage: useInMemoryMock,
            serviceIdentifier: serviceIdentifier
        )
        self.sessionDurationSeconds = sessionDurationSeconds
    }

    public var backendConfigurationStatusSummary: String {
        if isOnlineBackendConfigured {
            return "Connected to configured Daylight Authentication API endpoint."
        }
        return"Local Keychain Identity Provider active for on-device auth."
    }

    public func restoreSession(now: Date = Date()) async throws -> AuthenticatedSession? {
        guard let data = vault.readData(forKey: Self.activeSessionKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(AuthenticatedSession.self, from: data) else {
            vault.deleteData(forKey: Self.activeSessionKey)
            return nil
        }
        if session.isExpired(at: now) {
            vault.deleteData(forKey: Self.activeSessionKey)
            throw DaylightAuthenticationError.sessionExpired
        }
        return session
    }

    public func register(
        fullName: String,
        email: String,
        password: String,
        now: Date = Date()
    ) async throws -> AuthenticatedSession {
        guard providerMode != .remoteBackendAPI else {
            throw DaylightAuthenticationError.remoteBackendUnavailable
        }
        let validation = AuthFormValidator.validateRegistration(
            fullName: fullName,
            email: email,
            password: password,
            confirmPassword: password
        )
        if let firstError = validation.firstErrorMessage {
            throw DaylightAuthenticationError.invalidInput(firstError)
        }

        let normalizedEmail = AuthFormValidator.normalizeEmail(email)
        let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        var accounts = loadStoredAccounts()
        if accounts[normalizedEmail] != nil {
            throw DaylightAuthenticationError.registrationUnavailable
        }

        let userId = Self.deterministicOrRandomUserId(forEmail: normalizedEmail)
        let tenantId = "tenant_user_\(userId)"
        let saltHex = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let verifierHex = DaylightSecureAuthVault.derivePasswordVerifier(password: password, saltHex: saltHex)

        let record = StoredAccountCredentialRecord(
            userId: userId,
            email: normalizedEmail,
            fullName: cleanName,
            workspaceTenantId: tenantId,
            saltHex: saltHex,
            verifierHex: verifierHex,
            createdAt: now
        )
        accounts[normalizedEmail] = record
        saveStoredAccounts(accounts)

        let session = AuthenticatedSession(
            sessionId: "sess_\(UUID().uuidString.lowercased())",
            userId: userId,
            email: normalizedEmail,
            fullName: cleanName,
            workspaceTenantId: tenantId,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(sessionDurationSeconds),
            providerMode: providerMode
        )
        saveActiveSession(session)
        return session
    }

    public func login(
        email: String,
        password: String,
        now: Date = Date()
    ) async throws -> AuthenticatedSession {
        guard providerMode != .remoteBackendAPI else {
            throw DaylightAuthenticationError.remoteBackendUnavailable
        }
        let validation = AuthFormValidator.validateLogin(email: email, password: password)
        if let firstError = validation.firstErrorMessage {
            throw DaylightAuthenticationError.invalidInput(firstError)
        }

        let normalizedEmail = AuthFormValidator.normalizeEmail(email)
        let accounts = loadStoredAccounts()

        guard let account = accounts[normalizedEmail] else {
            // Perform dummy key derivation to mitigate timing side-channels and return uniform message
            _ = DaylightSecureAuthVault.derivePasswordVerifier(password: password, saltHex: "0000000000000000")
            throw DaylightAuthenticationError.invalidCredentials
        }

        let candidateVerifier = DaylightSecureAuthVault.derivePasswordVerifier(
            password: password,
            saltHex: account.saltHex
        )
        var authenticatedAccount = account
        if account.verifierVersion == 1 {
            guard DaylightSecureAuthVault.deriveLegacyPasswordVerifier(
                password: password,
                saltHex: account.saltHex
            ) == account.verifierHex else {
                throw DaylightAuthenticationError.invalidCredentials
            }
            authenticatedAccount.verifierHex = candidateVerifier
            authenticatedAccount.verifierVersion = 2
            var migratedAccounts = accounts
            migratedAccounts[normalizedEmail] = authenticatedAccount
            saveStoredAccounts(migratedAccounts)
        } else {
            guard candidateVerifier == account.verifierHex else {
                throw DaylightAuthenticationError.invalidCredentials
            }
        }

        let session = AuthenticatedSession(
            sessionId: "sess_\(UUID().uuidString.lowercased())",
            userId: authenticatedAccount.userId,
            email: authenticatedAccount.email,
            fullName: authenticatedAccount.fullName,
            workspaceTenantId: authenticatedAccount.workspaceTenantId,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(sessionDurationSeconds),
            providerMode: providerMode
        )
        saveActiveSession(session)
        return session
    }

    public func updateAuthenticatedUserName(_ newFullName: String) {
        let cleanName = newFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let data = vault.readData(forKey: Self.activeSessionKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let existingSession = try? decoder.decode(AuthenticatedSession.self, from: data) {
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
                saveActiveSession(updatedSession)

                let normalizedEmail = AuthFormValidator.normalizeEmail(existingSession.email)
                var accounts = loadStoredAccounts()
                if var record = accounts[normalizedEmail] {
                    record.fullName = cleanName
                    accounts[normalizedEmail] = record
                    saveStoredAccounts(accounts)
                }
            }
        }
    }

    public func logout(session: AuthenticatedSession?) async {
        vault.deleteData(forKey: Self.activeSessionKey)
    }

    // MARK: - Private Vault Helpers

    private func loadStoredAccounts() -> [String: StoredAccountCredentialRecord] {
        guard let data = vault.readData(forKey: Self.accountsRegistryKey) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: StoredAccountCredentialRecord].self, from: data)) ?? [:]
    }

    private func saveStoredAccounts(_ accounts: [String: StoredAccountCredentialRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(accounts) {
            vault.writeData(data, forKey: Self.accountsRegistryKey)
        }
    }

    private func saveActiveSession(_ session: AuthenticatedSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(session) {
            vault.writeData(data, forKey: Self.activeSessionKey)
        }
    }

    private static func deterministicOrRandomUserId(forEmail email: String) -> String {
        let digest = SHA256.hash(data: Data(email.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
