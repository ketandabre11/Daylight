import Foundation
import SwiftUI

// MARK: - Money Representation (Integer Minor Units / Cents)

/// All authoritative monetary amounts in Daylight Money are represented in integer minor units (AUD cents).
/// Binary floating-point is never used for financial storage or calculation.
public typealias MoneyCents = Int64

public enum AustralianMoneyFormatter {
    private static let audFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.numberStyle = .currency
        formatter.currencyCode = "AUD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let wholeDollarFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.numberStyle = .currency
        formatter.currencyCode = "AUD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Formats integer cents into standard Australian currency display (e.g., `$1,250.00` or `-$42.50`).
    public static func format(cents: MoneyCents, showPlusForPositive: Bool = false) -> String {
        let isNegative = cents < 0
        let absCents = abs(cents)
        let decimalAmount = Decimal(absCents) / Decimal(100)
        let formattedAbs = audFormatter.string(from: decimalAmount as NSDecimalNumber) ?? "$0.00"
        if isNegative {
            return "-\(formattedAbs)"
        } else if showPlusForPositive && cents > 0 {
            return "+\(formattedAbs)"
        }
        return formattedAbs
    }

    /// Formats integer cents to nearest whole dollar when compact display is appropriate.
    public static func formatWholeDollars(cents: MoneyCents) -> String {
        let isNegative = cents < 0
        let absCents = abs(cents)
        let roundedDollars = Decimal(absCents) / Decimal(100)
        let formattedAbs = wholeDollarFormatter.string(from: roundedDollars as NSDecimalNumber) ?? "$0"
        return isNegative ? "-\(formattedAbs)" : formattedAbs
    }

    /// Safely parses user-entered dollar string (e.g., `"1,250.50"`, `"$84.95"`, `"-12.30"`, `"(120.00)"`) into integer cents.
    public static func parseToCents(_ rawInput: String) -> MoneyCents? {
        let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isParentheticalNegative = trimmedInput.hasPrefix("(") && trimmedInput.hasSuffix(")")
        let cleaned = trimmedInput
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "AUD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard !cleaned.isEmpty else { return nil }
        guard let decimalValue = Decimal(string: cleaned, locale: Locale(identifier: "en_AU")) ?? Decimal(string: cleaned) else {
            return nil
        }
        var multiplied = decimalValue * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &multiplied, 0, .bankers)
        let cents = NSDecimalNumber(decimal: rounded).int64Value
        return isParentheticalNegative ? -abs(cents) : cents
    }
}

// MARK: - Australian Locale, Time Zone & Financial Year Utilities

public enum AustralianTimeZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case sydney = "Australia/Sydney"
    case melbourne = "Australia/Melbourne"
    case brisbane = "Australia/Brisbane"
    case perth = "Australia/Perth"
    case adelaide = "Australia/Adelaide"
    case hobart = "Australia/Hobart"
    case darwin = "Australia/Darwin"
    case canberra = "Australia/Canberra"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sydney: return "Sydney / NSW (AEST/AEDT)"
        case .melbourne: return "Melbourne / VIC (AEST/AEDT)"
        case .brisbane: return "Brisbane / QLD (AEST — No DST)"
        case .perth: return "Perth / WA (AWST — No DST)"
        case .adelaide: return "Adelaide / SA (ACST/ACDT)"
        case .hobart: return "Hobart / TAS (AEST/AEDT)"
        case .darwin: return "Darwin / NT (ACST — No DST)"
        case .canberra: return "Canberra / ACT (AEST/AEDT)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .sydney: return "Sydney (NSW)"
        case .melbourne: return "Melbourne (VIC)"
        case .brisbane: return "Brisbane (QLD)"
        case .perth: return "Perth (WA)"
        case .adelaide: return "Adelaide (SA)"
        case .hobart: return "Hobart (TAS)"
        case .darwin: return "Darwin (NT)"
        case .canberra: return "Canberra (ACT)"
        }
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: rawValue) ?? TimeZone(identifier: "Australia/Sydney") ?? .current
    }
}

public enum AustralianDateHelper {
    public static func timeZone(for timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> TimeZone {
        TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney") ?? .current
    }

    public static func calendar(for timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_AU")
        cal.timeZone = timeZone(for: timeZoneId)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// Formats a UTC timestamp in ISO-8601 local date (`yyyy-MM-dd`) for the user's Australian time zone.
    public static func formatISODate(_ date: Date, timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone(for: timeZoneId)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Formats a UTC timestamp in Australian format, e.g. `22 October 2026`.
    public static func formatMediumDate(_ date: Date, timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Formats a UTC timestamp in short Australian format, e.g. `22 Oct 2026`.
    public static func formatShortDate(_ date: Date, timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    /// Formats date and time in Australian locale, e.g. `22 Oct 2026, 2:15 pm`.
    public static func formatDateTime(_ date: Date, timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: date)
    }

    /// Computes the Australian Financial Year (1 July to 30 June) containing the given date.
    /// For example, 22 October 2026 belongs to FY2026–27 (1 July 2026 00:00:00 to 30 June 2027 23:59:59).
    public static func financialYearBounds(for date: Date, timeZoneId: String = AustralianTimeZone.sydney.rawValue) -> (label: String, start: Date, end: Date) {
        let cal = calendar(for: timeZoneId)
        let components = cal.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 10

        let startYear = (month >= 7) ? year : (year - 1)
        let endYear = startYear + 1

        let startDate = cal.date(from: DateComponents(year: startYear, month: 7, day: 1, hour: 0, minute: 0, second: 0)) ?? date
        let endDate = cal.date(from: DateComponents(year: endYear, month: 6, day: 30, hour: 23, minute: 59, second: 59)) ?? date
        let shortEnd = String(endYear % 100)
        return ("FY\(startYear)–\(shortEnd)", startDate, endDate)
    }
}

// MARK: - Australian Spending & Income Categories

/// Covers all 25 required Australian financial categories with semantic icons and colours.
public enum AustralianCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case rentAndMortgage = "rent_and_mortgage"
    case groceries = "groceries_supermarkets"
    case cafesAndTakeaway = "cafes_coffee_takeaway"
    case restaurantsAndDelivery = "restaurants_food_delivery"
    case publicTransport = "public_transport_opal_myki"
    case fuelTollsVehicle = "fuel_tolls_parking_vehicle"
    case utilitiesAndInternet = "electricity_gas_water_internet"
    case mobilePhone = "mobile_phone"
    case insurance = "insurance"
    case healthcareMedicare = "healthcare_medicare_pharmacy"
    case childcareEducation = "childcare_education"
    case hecsHelp = "hecs_help_student"
    case councilRatesStrata = "council_rates_strata"
    case gymFitness = "gym_memberships"
    case streamingSubscriptions = "streaming_digital_subscriptions"
    case shoppingRetail = "shopping_retail"
    case domesticTravelHolidays = "domestic_travel_holidays"
    case buyNowPayLater = "buy_now_pay_later"
    case creditCardRepayment = "credit_card_repayments"
    case personalLoansDebt = "personal_loans_debt"
    case salaryWagesIncome = "salary_wages_income"
    case governmentPayments = "government_payments_centrelink"
    case superannuation = "superannuation"
    case bankFeesInterestRefunds = "bank_fees_interest_refunds"
    case ownAccountTransfer = "own_account_transfers"
    case cashAndUnclassified = "cash_withdrawals_unclassified"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rentAndMortgage: return "Rent & Mortgage"
        case .groceries: return "Groceries & Supermarkets"
        case .cafesAndTakeaway: return "Cafes, Coffee & Takeaway"
        case .restaurantsAndDelivery: return "Restaurants & Food Delivery"
        case .publicTransport: return "Public Transport (Opal / Myki)"
        case .fuelTollsVehicle: return "Fuel, Tolls, Parking & Vehicle"
        case .utilitiesAndInternet: return "Electricity, Gas, Water & Internet"
        case .mobilePhone: return "Mobile Phone Bills"
        case .insurance: return "Insurance"
        case .healthcareMedicare: return "Healthcare, Medicare & Pharmacy"
        case .childcareEducation: return "Childcare & Education"
        case .hecsHelp: return "HECS-HELP & Student Commitments"
        case .councilRatesStrata: return "Council Rates & Strata"
        case .gymFitness: return "Gym & Fitness"
        case .streamingSubscriptions: return "Streaming & Subscriptions"
        case .shoppingRetail: return "Shopping & Retail"
        case .domesticTravelHolidays: return "Domestic Travel & Holidays"
        case .buyNowPayLater: return "Buy Now, Pay Later (BNPL)"
        case .creditCardRepayment: return "Credit Card Repayments"
        case .personalLoansDebt: return "Personal Loans & Debt"
        case .salaryWagesIncome: return "Salary, Wages & Contractor Income"
        case .governmentPayments: return "Government & Family Payments"
        case .superannuation: return "Superannuation Contributions"
        case .bankFeesInterestRefunds: return "Bank Fees, Interest & Refunds"
        case .ownAccountTransfer: return "Transfers Between Own Accounts"
        case .cashAndUnclassified: return "Cash Withdrawals & Unclassified"
        }
    }

    public var symbolName: String {
        switch self {
        case .rentAndMortgage: return "house.fill"
        case .groceries: return "cart.fill"
        case .cafesAndTakeaway: return "cup.and.saucer.fill"
        case .restaurantsAndDelivery: return "fork.knife"
        case .publicTransport: return "tram.fill"
        case .fuelTollsVehicle: return "car.fill"
        case .utilitiesAndInternet: return "bolt.fill"
        case .mobilePhone: return "iphone"
        case .insurance: return "shield.checkered"
        case .healthcareMedicare: return "cross.case.fill"
        case .childcareEducation: return "graduationcap.fill"
        case .hecsHelp: return "book.closed.fill"
        case .councilRatesStrata: return "building.2.fill"
        case .gymFitness: return "figure.run"
        case .streamingSubscriptions: return "play.tv.fill"
        case .shoppingRetail: return "bag.fill"
        case .domesticTravelHolidays: return "airplane"
        case .buyNowPayLater: return "calendar.badge.clock"
        case .creditCardRepayment: return "creditcard.and.123"
        case .personalLoansDebt: return "banknote.fill"
        case .salaryWagesIncome: return "dollarsign.circle.fill"
        case .governmentPayments: return "building.columns.fill"
        case .superannuation: return "chart.line.uptrend.xyaxis"
        case .bankFeesInterestRefunds: return "arrow.uturn.backward.circle.fill"
        case .ownAccountTransfer: return "arrow.left.arrow.right.circle.fill"
        case .cashAndUnclassified: return "questionmark.circle.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .rentAndMortgage, .councilRatesStrata: return .indigo
        case .groceries: return Color(red: 0.12, green: 0.56, blue: 0.34)
        case .cafesAndTakeaway, .restaurantsAndDelivery: return .orange
        case .publicTransport, .fuelTollsVehicle: return .blue
        case .utilitiesAndInternet, .mobilePhone: return .teal
        case .insurance, .healthcareMedicare: return .pink
        case .childcareEducation, .hecsHelp: return .cyan
        case .gymFitness: return .mint
        case .streamingSubscriptions, .shoppingRetail: return .purple
        case .domesticTravelHolidays: return .brown
        case .buyNowPayLater, .personalLoansDebt: return Color(red: 0.78, green: 0.42, blue: 0.12)
        case .creditCardRepayment, .ownAccountTransfer: return .gray
        case .salaryWagesIncome, .governmentPayments, .superannuation: return Color(red: 0.08, green: 0.54, blue: 0.28)
        case .bankFeesInterestRefunds, .cashAndUnclassified: return .secondary
        }
    }

    /// Indicates whether this category represents typical fixed housing/bill commitments vs everyday flexible spending.
    public var isDefaultFixedCommitment: Bool {
        switch self {
        case .rentAndMortgage, .utilitiesAndInternet, .mobilePhone, .insurance, .childcareEducation, .hecsHelp, .councilRatesStrata, .gymFitness, .streamingSubscriptions, .personalLoansDebt:
            return true
        default:
            return false
        }
    }

    public static var expenseCategories: [AustralianCategory] {
        allCases.filter {
            $0 != .salaryWagesIncome && $0 != .governmentPayments && $0 != .ownAccountTransfer && $0 != .creditCardRepayment
        }
    }
}

// MARK: - Employment, Pay Frequency & Budgeting Methods

public enum EmploymentIncomeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case salariedEmployee = "salaried_employee"
    case casualOrShift = "casual_or_shift"
    case contractorOrFreelancer = "contractor_or_freelancer"
    case studentOrApprentice = "student_or_apprentice"
    case familyHousehold = "family_household"
    case retireeOrPension = "retiree_or_pension"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .salariedEmployee: return "Salaried Employee (PAYG)"
        case .casualOrShift: return "Casual / Shift Worker"
        case .contractorOrFreelancer: return "Contractor / Sole Trader (ABN)"
        case .studentOrApprentice: return "Student / Apprentice"
        case .familyHousehold: return "Family / Shared Household"
        case .retireeOrPension: return "Retiree / Super Income Stream"
        }
    }
}

public enum PayFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly = "weekly"
    case fortnightly = "fortnightly"
    case monthly = "monthly"
    case irregular = "irregular"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .fortnightly: return "Fortnightly"
        case .monthly: return "Monthly"
        case .irregular: return "Irregular (28-day)"
        }
    }

    public var nominalPeriodDays: Int {
        switch self {
        case .weekly: return 7
        case .fortnightly: return 14
        case .monthly: return 30
        case .irregular: return 28
        }
    }
}

public enum BudgetingMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case simpleDailyAllowance = "simple_daily_allowance"
    case monthlyFlexible = "monthly_flexible"
    case categorySpecific = "category_specific"
    case payCycle = "pay_cycle"
    case savingsFirst = "savings_first"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .simpleDailyAllowance: return "Daily Allowance"
        case .monthlyFlexible: return "Monthly Flexible"
        case .categorySpecific: return "Category Envelopes"
        case .payCycle: return "Pay-Cycle Aligned"
        case .savingsFirst: return "Savings-First"
        case .custom: return "Custom Cap"
        }
    }

    public var explanation: String {
        switch self {
        case .simpleDailyAllowance:
            return "Divides your remaining flexible budget equally across the days left in your period."
        case .monthlyFlexible:
            return "Tracks all flexible spending against a single calendar-month pool after bills and savings."
        case .categorySpecific:
            return "Sets dedicated limits for key categories like Groceries, Cafes, and Transport."
        case .payCycle:
            return "Aligns your spending allowance directly to your next Australian payday."
        case .savingsFirst:
            return "Locks away your savings goal contribution first, then calculates daily safe spending."
        case .custom:
            return "Uses your manually specified flexible spending cap for the active period."
        }
    }
}

// MARK: - User Profile & Preferences

public struct UserProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var preferredName: String
    public var email: String
    public var countryCode: String // Default: "AU"
    public var currencyCode: String // Default: "AUD"
    public var timeZoneId: String // Default: "Australia/Sydney"
    public var employmentType: EmploymentIncomeType
    public var payFrequency: PayFrequency
    public var typicalTakeHomePayCents: MoneyCents
    public var nextPayDate: Date
    public var savingsTargetPerPeriodCents: MoneyCents
    public var customFlexibleCapCents: MoneyCents?
    public var preferredBudgetingMethod: BudgetingMethod
    public var enableBudgetRollover: Bool
    public var themePreference: AppThemePreference
    public var onboardingCompleted: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

// MARK: - Accounts, Open Banking (CDR) Connections & Consents

public enum FinancialAccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case everydayTransaction = "everyday_transaction"
    case highInterestSavings = "high_interest_savings"
    case mortgageOffset = "mortgage_offset"
    case creditCard = "credit_card"
    case hecsOrLoan = "hecs_or_loan"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .everydayTransaction: return "Everyday Transaction"
        case .highInterestSavings: return "Savings Account"
        case .mortgageOffset: return "Home Loan Offset"
        case .creditCard: return "Credit Card"
        case .hecsOrLoan: return "HECS-HELP / Loan Account"
        }
    }

    public var isAssetAccount: Bool {
        switch self {
        case .everydayTransaction, .highInterestSavings, .mortgageOffset:
            return true
        case .creditCard, .hecsOrLoan:
            return false
        }
    }

    public var symbolName: String {
        switch self {
        case .everydayTransaction: return "building.columns.fill"
        case .highInterestSavings: return "banknote.fill"
        case .mortgageOffset: return "house.fill"
        case .creditCard: return "creditcard.fill"
        case .hecsOrLoan: return "doc.text.fill"
        }
    }
}

public enum AccountConnectionStatus: String, Codable, CaseIterable, Sendable {
    case manual = "manual"
    case demoSynthetic = "demo_synthetic"
    case cdrSandboxConnected = "cdr_sandbox_connected"
    case cdrRefreshFailed = "cdr_refresh_failed"
    case cdrConsentExpired = "cdr_consent_expired"
    case disconnected = "disconnected"

    public var displayName: String {
        switch self {
        case .manual: return "Manual / Statement Import"
        case .demoSynthetic: return "Synthetic Demo Feed (Not Live Bank)"
        case .cdrSandboxConnected: return "CDR Open Banking Adapter (Sandbox)"
        case .cdrRefreshFailed: return "Sync Delayed — Retry Available"
        case .cdrConsentExpired: return "CDR Consent Expired"
        case .disconnected: return "Disconnected"
        }
    }
}

public struct ConsentRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var institutionName: String
    public var providerAdapterName: String
    public var scopesGranted: [String]
    public var grantedAt: Date
    public var expiresAt: Date
    public var revokedAt: Date?
    public var isSandboxSimulation: Bool
    public var statusNote: String
}

public struct FinancialAccount: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var institutionName: String
    public var nickname: String
    public var accountType: FinancialAccountType
    public var maskedAccountNumber: String // e.g., "•••• 4821" — never full BSB/Account number
    public var currencyCode: String
    /// Available balance (funds available right now after pending holds, or remaining credit)
    public var availableBalanceCents: MoneyCents
    /// Current / ledger balance (posted balance; negative for credit cards / loans owing)
    public var currentBalanceCents: MoneyCents
    public var balanceUpdatedAt: Date
    public var connectionStatus: AccountConnectionStatus
    public var lastSuccessfulSyncAt: Date?
    public var lastSyncErrorMessage: String?
    public var dataCoverageDescription: String
    public var consentRecordId: UUID?
    public var includeInSafeToSpendCash: Bool
}

// MARK: - Transactions, Splits, Merchant Rules & Reconciliations

public enum TransactionDirection: String, Codable, CaseIterable, Sendable {
    case debit = "debit"   // Outflow / purchase
    case credit = "credit" // Inflow / income / refund
}

public enum TransactionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending = "pending"
    case posted = "posted"
    case reversed = "reversed"
    case refunded = "refunded"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .posted: return "Posted"
        case .reversed: return "Reversed"
        case .refunded: return "Refunded"
        }
    }
}

/// Explicit domain classification of how a transaction behaves in budgeting & historical reports.
public enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense = "expense"
    case income = "income"
    case ownAccountTransfer = "own_account_transfer"
    case creditCardPurchase = "credit_card_purchase"
    case creditCardRepayment = "credit_card_repayment"
    case refund = "refund"
    case reversal = "reversal"
    case cashWithdrawal = "cash_withdrawal"
    case feeOrInterest = "fee_or_interest"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .expense: return "Everyday / Bill Expense"
        case .income: return "Income / Deposit"
        case .ownAccountTransfer: return "Internal Transfer (Own Accounts)"
        case .creditCardPurchase: return "Credit Card Purchase"
        case .creditCardRepayment: return "Credit Card Bill Repayment"
        case .refund: return "Merchant Refund / Rebate"
        case .reversal: return "Bank Reversal"
        case .cashWithdrawal: return "ATM / Cash Out"
        case .feeOrInterest: return "Bank Fee or Interest"
        }
    }
}

public enum TransactionSource: String, Codable, CaseIterable, Sendable {
    case manualEntry = "manual_entry"
    case csvStatementImport = "csv_statement_import"
    case demoSynthetic = "demo_synthetic"
    case cdrSandboxFeed = "cdr_sandbox_feed"

    public var displayName: String {
        switch self {
        case .manualEntry: return "Manual Entry"
        case .csvStatementImport: return "CSV Statement Import"
        case .demoSynthetic: return "Synthetic Demo Data"
        case .cdrSandboxFeed: return "CDR Sandbox Feed"
        }
    }
}

public struct TransactionSplit: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var category: AustralianCategory
    public var amountCents: MoneyCents
    public var note: String
    public var excludeFromBudget: Bool
}

public struct TransactionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var accountId: UUID
    public var sourceTransactionId: String?
    public var reconciliationFingerprint: String
    public var merchantName: String
    public var rawDescription: String
    public var occurredAt: Date
    /// Positive integer cents; direction indicates debit vs credit.
    public var amountCents: MoneyCents
    public var direction: TransactionDirection
    public var category: AustralianCategory
    public var classificationConfidence: Double // 0.0 to 1.0; < 0.70 shows uncertainty indicator
    public var status: TransactionStatus
    public var kind: TransactionKind
    public var isRecurring: Bool
    public var paymentRail: String? // e.g., "Osko / PayID", "BPAY", "Direct Debit", "eftpos / Card"
    public var source: TransactionSource
    public var userNote: String
    public var excludeFromBudget: Bool
    public var linkedOriginalTransactionId: UUID? // For refunds or reversals linked to original purchase
    public var splits: [TransactionSplit]
    public var calculationVersion: Int
    public var updatedAt: Date
}

public struct MerchantRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var matchSubstring: String
    public var normalizedMerchantName: String
    public var assignedCategory: AustralianCategory
    public var applyToFutureOnly: Bool
    public var createdAt: Date
}

// MARK: - Budgets, Fixed Commitments & Safe-to-Spend Summary

public struct FixedCommitment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var title: String
    public var category: AustralianCategory
    public var amountCents: MoneyCents
    public var frequency: PayFrequency
    public var nextDueDate: Date
    public var isConfirmed: Bool
}

public struct CategoryBudget: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var category: AustralianCategory
    public var limitCents: MoneyCents
    public var rolloverEnabled: Bool
    public var rolloverBalanceCents: MoneyCents
    public var periodType: PayFrequency
    public var updatedAt: Date
}

public struct CategoryBudgetProgress: Identifiable, Equatable, Sendable {
    public var id: String { category.rawValue }
    public let category: AustralianCategory
    public let budgetedCents: MoneyCents
    public let netSpentCents: MoneyCents
    public let remainingCents: MoneyCents
    public let percentageUsed: Double
    public let projectedEndOfPeriodCents: MoneyCents
    public let isOverBudget: Bool
    public let recentTransactions: [TransactionRecord]
}

/// Authoritative output from `FinancialCalculationEngine` answering the 5 core user questions.
public struct DailyAllowanceSummary: Equatable, Sendable {
    public let periodStart: Date
    public let periodEnd: Date
    public let totalDaysInPeriod: Int
    public let elapsedDaysInPeriod: Int
    public let remainingDaysInPeriod: Int // Includes today (>= 1)

    /// 1. Bank account balances (distinct from budgeting figures!)
    public let everydayAvailableBankBalanceCents: MoneyCents
    public let totalLiquidCashAcrossAccountsCents: MoneyCents
    public let totalCreditCardAndDebtBalanceCents: MoneyCents

    /// 2. Budget & Commitment breakdown for the active period
    public let periodTakeHomeIncomeCents: MoneyCents
    public let totalFixedCommitmentsForPeriodCents: MoneyCents
    public let unpaidFixedCommitmentsRemainingCents: MoneyCents
    public let plannedSavingsForPeriodCents: MoneyCents
    public let availableCashAfterCommitmentsCents: MoneyCents

    /// 3. Flexible spending & Daily Safe-to-Spend
    public let totalFlexibleBudgetForPeriodCents: MoneyCents
    public let baselineDailyAllowanceCents: MoneyCents
    public let flexibleSpentPriorToTodayCents: MoneyCents
    public let flexibleSpentTodayCents: MoneyCents
    public let totalFlexibleSpentInPeriodCents: MoneyCents
    public let remainingFlexibleBudgetForPeriodCents: MoneyCents

    /// Today's dynamic safe-to-spend target at the start of today (remaining flexible budget / remaining days)
    public let todaysStartingAllowanceCents: MoneyCents
    /// How much the user can still comfortably spend today (can be negative if exceeded today)
    public let todaysRemainingAllowanceCents: MoneyCents
    public let forecastEndOfPeriodFlexibleSpendCents: MoneyCents

    /// Human-readable step-by-step audit explanation of how the figure was derived.
    public let calculationSteps: [String]
    public let budgetingMethodUsed: BudgetingMethod
    public let calculationVersion: Int
}

// MARK: - Recurring Payment Predictions (Bills & Subscriptions)

public enum RecurringFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly = "weekly"
    case fortnightly = "fortnightly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case annual = "annual"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .fortnightly: return "Fortnightly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .annual: return "Annual"
        }
    }

    public var approximateDays: Int {
        switch self {
        case .weekly: return 7
        case .fortnightly: return 14
        case .monthly: return 30
        case .quarterly: return 91
        case .annual: return 365
        }
    }
}

public enum PredictionConfidence: String, Codable, CaseIterable, Sendable {
    case confirmedSchedule = "confirmed_schedule"
    case high = "high"
    case medium = "medium"
    case low = "low"

    public var displayName: String {
        switch self {
        case .confirmedSchedule: return "Confirmed Schedule"
        case .high: return "High Confidence"
        case .medium: return "Predicted Pattern"
        case .low: return "Possible Recurring"
        }
    }
}

public struct RecurringPaymentPrediction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var merchantName: String
    public var category: AustralianCategory
    public var expectedAmountCents: MoneyCents
    public var frequency: RecurringFrequency
    public var nextExpectedDate: Date
    public var lastPaymentDate: Date
    public var confidence: PredictionConfidence
    public var isConfirmedByUser: Bool
    public var isDismissed: Bool
    public var paymentRail: String
    public var linkedTransactionIds: [UUID]
}

// MARK: - Savings Goals

public struct SavingsContribution: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var amountCents: MoneyCents
    public var note: String
}

public struct SavingsGoal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var name: String
    public var iconName: String
    public var targetAmountCents: MoneyCents
    public var currentSavedCents: MoneyCents
    public var targetDate: Date?
    public var linkedAccountId: UUID?
    public var contributions: [SavingsContribution]
    public var assumptionsNote: String
    public var createdAt: Date
}

// MARK: - Deterministic Insights & Notifications

public enum InsightSeverity: String, Codable, Sendable {
    case positive
    case neutral
    case headsUp
}

public struct FinancialInsight: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let calculationDetail: String
    public let actionableRecommendation: String
    public let severity: InsightSeverity
    public let relatedCategory: AustralianCategory?
    public let supportingTransactionIds: [UUID]
    public let isDeterministic: Bool
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var dailySummaryEnabled: Bool
    public var dailySummaryHour: Int // e.g. 19 (7:00 PM local)
    public var budgetThresholdAlertsEnabled: Bool
    public var upcomingBillRemindersEnabled: Bool
    public var paydayRemindersEnabled: Bool
    public var recurringChangeAlertsEnabled: Bool
    public var unusualSpendingAlertsEnabled: Bool
    public var hideExactAmountsInPreviews: Bool
}

public struct AppNotification: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var title: String
    public var body: String
    public var categoryTag: String
    public var createdAt: Date
    public var isRead: Bool
}

// MARK: - Statement Import & Audit Events

public struct CSVColumnMapping: Codable, Equatable, Sendable {
    public var dateColumnIndex: Int
    public var descriptionColumnIndex: Int
    public var amountColumnIndex: Int?
    public var debitColumnIndex: Int?
    public var creditColumnIndex: Int?
    public var hasHeaderRow: Bool
}

public struct ParsedCSVRowPreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let rowNumber: Int
    public let rawLine: String
    public let parsedDate: Date?
    public let parsedDescription: String
    public let parsedAmountCents: MoneyCents?
    public let parsedDirection: TransactionDirection
    public let inferredCategory: AustralianCategory
    public let inferredKind: TransactionKind
    public let classificationConfidence: Double
    public let fingerprint: String
    public let isDuplicate: Bool
    public let validationError: String?
}

public struct ImportJobRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var fileName: String
    public var targetAccountId: UUID
    public var idempotencyKey: String
    public var totalRows: Int
    public var importedCount: Int
    public var duplicateSkippedCount: Int
    public var rejectedCount: Int
    public var status: String // "completed", "failed", "partial"
    public var createdAt: Date
}

public struct AuditEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tenantId: String
    public var action: String
    public var entityType: String
    public var entityId: String
    public var summary: String
    public var createdAt: Date
}

// MARK: - Persistent Categories, Subcategories, Memberships, Sessions & Import Issues (Schema v3)

public enum TransactionCategoryType: String, Codable, CaseIterable, Sendable {
    case expense = "expense"
    case income = "income"
    case transfer = "transfer"
}

/// Represents a persistent system or workspace-scoped custom category or subcategory in SQLite.
public struct TransactionCategoryRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String // e.g. "system:groceries" or "custom:tenant_personal_au:<uuid>"
    public var parentCategoryId: String?
    public var tenantId: String // "__SYSTEM__" for built-in AU categories, or workspace tenantId for custom categories
    public var categoryCode: String
    public var name: String
    public var iconName: String
    public var displayOrder: Int
    public var categoryType: TransactionCategoryType
    public var isSystemDefault: Bool
    public var isCustom: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        parentCategoryId: String? = nil,
        tenantId: String,
        categoryCode: String,
        name: String,
        iconName: String,
        displayOrder: Int,
        categoryType: TransactionCategoryType,
        isSystemDefault: Bool,
        isCustom: Bool,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentCategoryId = parentCategoryId
        self.tenantId = tenantId
        self.categoryCode = categoryCode
        self.name = name
        self.iconName = iconName
        self.displayOrder = displayOrder
        self.categoryType = categoryType
        self.isSystemDefault = isSystemDefault
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Row-level rejected statement import issue persisted so rejected rows remain inspectable & repairable across app restarts.
public struct ImportJobIssueRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var importJobId: UUID
    public var tenantId: String
    public var rowNumber: Int
    public var sanitizedRawLine: String
    public var validationError: String
    public var isRepaired: Bool
    public var repairedTransactionId: UUID?
    public var createdAt: Date
}

/// Workspace ownership and membership record enforcing tenant authorization boundaries.
public struct WorkspaceMembershipRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var tenantId: String
    public var userId: String
    public var role: String // "owner", "member", "viewer"
    public var createdAt: Date
}

/// Non-secret session metadata (never stores passwords, password hashes, or bearer tokens).
public struct AppSessionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public var sessionId: String
    public var userId: String
    public var tenantId: String
    public var authProvider: String
    public var createdAt: Date
    public var lastActiveAt: Date
    public var isActive: Bool
}

