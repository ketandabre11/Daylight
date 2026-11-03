import Foundation

// MARK: - Recognized Merchant Model

public struct RecognizedMerchant: Equatable, Sendable {
    /// Canonical, human-friendly merchant display name (e.g. "Woolworths", "Coles Express", "Uber", "Spotify").
    public let canonicalName: String
    /// Original un-normalized transaction string as received from the bank.
    public let rawDescription: String
    /// Default or most common category associated with this merchant in Australia.
    public let defaultCategory: AustralianCategory?
    /// Whether this is a recognized known merchant in our Australian directory or a normalized unknown merchant.
    public let isKnownMerchant: Bool
    /// Confidence score of the normalization and recognition (0.0 to 1.0).
    public let confidence: Double
    /// Detected terminal ID, store number, or reference if extracted (e.g. "0321", "1234").
    public let detectedTerminalId: String?
    /// Detected Australian city, suburb, or state code if extracted (e.g. "SYD", "NSW").
    public let detectedLocation: String?
    /// Detected online or delivery indicator (e.g. "Online", "In-Store", "Delivery").
    public let channel: String?

    public init(
        canonicalName: String,
        rawDescription: String,
        defaultCategory: AustralianCategory?,
        isKnownMerchant: Bool,
        confidence: Double,
        detectedTerminalId: String? = nil,
        detectedLocation: String? = nil,
        channel: String? = nil
    ) {
        self.canonicalName = canonicalName
        self.rawDescription = rawDescription
        self.defaultCategory = defaultCategory
        self.isKnownMerchant = isKnownMerchant
        self.confidence = confidence
        self.detectedTerminalId = detectedTerminalId
        self.detectedLocation = detectedLocation
        self.channel = channel
    }

    /// British/Australian English spelling aliases
    public var recognisedName: String { canonicalName }
    public var isUnknown: Bool { !isKnownMerchant }
}

// MARK: - Merchant Recognition & Normalisation Service

/// Deterministic Australian merchant recognition and description normalisation service.
/// Strips bank payment prefixes, terminal IDs, store numbers, and location suffixes while
/// accurately disambiguating similar brands (e.g. "Coles" vs "Coles Express", "Uber" vs "Uber Eats").
public final class MerchantRecognitionService: Sendable {
    public static let shared = MerchantRecognitionService()

    public init() {}

    // MARK: - Common Banking & Payment Rail Prefixes to Strip

    private static let paymentPrefixes: [String] = [
        "VISA DEBIT PURCHASE ",
        "VISA PURCHASE ",
        "VISA DEBIT ",
        "EFTPOS DEBIT ",
        "EFTPOS PURCHASE ",
        "EFTPOS ",
        "DIRECT DEBIT ",
        "DIRECT DEBIT PURCHASE ",
        "DDR ",
        "OSKO PAYMENT TO ",
        "OSKO PAYMENT ",
        "OSKO TO ",
        "OSKO ",
        "PAYID TO ",
        "PAYID PAYMENT ",
        "PAYID ",
        "NPP PAYMENT TO ",
        "NPP TO ",
        "NPP ",
        "PURCHASE ",
        "CARD PURCHASE ",
        "DEBIT CARD PURCHASE ",
        "POS PURCHASE ",
        "POS DEBIT ",
        "POS ",
        "SQ *",
        "SQ ",
        "PAYPAL *",
        "PAYPAL ",
        "PP*",
        "STRIPE *",
        "STRIPE "
    ]

    // MARK: - Australian State & Capital Suffixes

    private static let australianLocationTokens: Set<String> = [
        "SYD", "SYDNEY", "MELB", "MELBOURNE", "BNE", "BRISBANE", "PERTH", "ADL", "ADELAIDE",
        "CBR", "CANBERRA", "HBA", "HOBART", "DRW", "DARWIN", "GC", "GOLD COAST",
        "NSW", "VIC", "QLD", "WA", "SA", "TAS", "ACT", "NT",
        "AU", "AUS", "AUSTRALIA"
    ]

    // MARK: - Curated Australian Merchant Directory

    private struct CuratedMerchantEntry {
        let canonicalName: String
        let category: AustralianCategory
        let aliases: [String]
        let channel: String?
        let baseConfidence: Double
    }

    private static let curatedDirectory: [CuratedMerchantEntry] = [
        // Supermarkets & Groceries
        CuratedMerchantEntry(
            canonicalName: "Woolworths",
            category: .groceries,
            aliases: ["WOOLWORTHS", "METRO WOOLWORTHS", "WOOLIES", "SAFEWAY"],
            channel: nil,
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Woolworths Online",
            category: .groceries,
            aliases: ["WOOLWORTHS ONLINE", "WOW ONLINE"],
            channel: "Online",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Coles",
            category: .groceries,
            aliases: ["COLES SUPERMARKET", "COLES SUPERMARKETS", "COLES ONLINE", "COLES ", "COLES"],
            channel: nil,
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "ALDI",
            category: .groceries,
            aliases: ["ALDI STORES", "ALDI ", "ALDI"],
            channel: nil,
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Harris Farm Markets",
            category: .groceries,
            aliases: ["HARRIS FARM MARKETS", "HARRIS FARM"],
            channel: nil,
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "IGA",
            category: .groceries,
            aliases: ["SUPA IGA", "IGA SUPERMARKET", "IGA "],
            channel: nil,
            baseConfidence: 0.95
        ),
        CuratedMerchantEntry(
            canonicalName: "Costco",
            category: .groceries,
            aliases: ["COSTCO WHOLESALE", "COSTCO FUEL", "COSTCO"],
            channel: nil,
            baseConfidence: 0.96
        ),

        // Fuel & Convenience (Disambiguated from Supermarkets)
        CuratedMerchantEntry(
            canonicalName: "Coles Express",
            category: .fuelTollsVehicle,
            aliases: ["COLES EXPRESS", "SHELL COLES EXPRESS", "COLES EXPRESS SERVICE"],
            channel: "Fuel & Convenience",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Ampol",
            category: .fuelTollsVehicle,
            aliases: ["AMPOL AUSTRALIA", "AMPOL WOOLWORTHS", "CALTEX WOOLWORTHS", "CALTEX", "AMPOL "],
            channel: "Fuel",
            baseConfidence: 0.95
        ),
        CuratedMerchantEntry(
            canonicalName: "BP",
            category: .fuelTollsVehicle,
            aliases: ["BP CONNECT", "BP SERVICE STATION", "BP "],
            channel: "Fuel",
            baseConfidence: 0.95
        ),
        CuratedMerchantEntry(
            canonicalName: "7-Eleven",
            category: .fuelTollsVehicle,
            aliases: ["7-ELEVEN FUEL", "7-ELEVEN CONVENIENCE", "7 ELEVEN", "7-ELEVEN"],
            channel: nil,
            baseConfidence: 0.95
        ),
        CuratedMerchantEntry(
            canonicalName: "United Petroleum",
            category: .fuelTollsVehicle,
            aliases: ["UNITED PETROLEUM", "UNITED FUEL"],
            channel: "Fuel",
            baseConfidence: 0.95
        ),

        // Public Transport & Tolls
        CuratedMerchantEntry(
            canonicalName: "Opal",
            category: .publicTransport,
            aliases: ["OPAL TOP UP", "OPAL FARE", "TRANSPORT FOR NSW", "TFNSW", "OPAL"],
            channel: "Transit",
            baseConfidence: 0.99
        ),
        CuratedMerchantEntry(
            canonicalName: "PTV Myki",
            category: .publicTransport,
            aliases: ["MYKI TOPUP", "MYKI TOP UP", "PUBLIC TRANSPORT VICTORIA", "PTV ", "MYKI", "PTV"],
            channel: "Transit",
            baseConfidence: 0.99
        ),
        CuratedMerchantEntry(
            canonicalName: "Translink QLD",
            category: .publicTransport,
            aliases: ["TRANSLINK GO CARD", "TRANSLINK QLD", "TRANSLINK"],
            channel: "Transit",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Linkt",
            category: .fuelTollsVehicle,
            aliases: ["LINKT TOLLS", "LINKT AUTO TOP UP", "ROAM EXPRESS", "E-TOLL", "LINKT"],
            channel: "Tolls",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "EastLink",
            category: .fuelTollsVehicle,
            aliases: ["EASTLINK TOLLS", "EASTLINK"],
            channel: "Tolls",
            baseConfidence: 0.97
        ),

        // Rideshare & Transport
        CuratedMerchantEntry(
            canonicalName: "Uber",
            category: .publicTransport,
            aliases: ["UBER *TRIP", "UBER TRIP", "UBER BV", "UBER.COM", "UBER RIDES"],
            channel: "Rideshare",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "DiDi",
            category: .fuelTollsVehicle,
            aliases: ["DIDI MOBILITY", "DIDI RIDES", "DIDI "],
            channel: "Rideshare",
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "13cabs",
            category: .fuelTollsVehicle,
            aliases: ["13CABS TAXI", "13CABS", "13 CABS", "SILVER SERVICE TAXI"],
            channel: "Taxi",
            baseConfidence: 0.95
        ),

        // Food Delivery & Dining
        CuratedMerchantEntry(
            canonicalName: "Uber Eats",
            category: .restaurantsAndDelivery,
            aliases: ["UBER *EATS", "UBER EATS", "UBEREATS"],
            channel: "Delivery",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "DoorDash",
            category: .restaurantsAndDelivery,
            aliases: ["DOORDASH *", "DOORDASH AUSTRALIA", "DOORDASH"],
            channel: "Delivery",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Menulog",
            category: .restaurantsAndDelivery,
            aliases: ["MENULOG PTY LTD", "MENULOG AUSTRALIA", "MENULOG"],
            channel: "Delivery",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Guzman y Gomez",
            category: .cafesAndTakeaway,
            aliases: ["GUZMAN Y GOMEZ", "GYG "],
            channel: "Quick Service",
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "McDonald's",
            category: .cafesAndTakeaway,
            aliases: ["MCDONALD'S", "MCDONALDS", "MACCAS"],
            channel: "Quick Service",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Grill'd",
            category: .cafesAndTakeaway,
            aliases: ["GRILL'D HEALTHY BURGERS", "GRILL'D"],
            channel: "Quick Service",
            baseConfidence: 0.96
        ),

        // Digital Subscriptions & Entertainment
        CuratedMerchantEntry(
            canonicalName: "Spotify",
            category: .streamingSubscriptions,
            aliases: ["SPOTIFY P AU", "SPOTIFY AUSTRALIA", "SPOTIFY.COM", "SPOTIFY"],
            channel: "Subscription",
            baseConfidence: 0.99
        ),
        CuratedMerchantEntry(
            canonicalName: "Netflix",
            category: .streamingSubscriptions,
            aliases: ["NETFLIX.COM", "NETFLIX AUSTRALIA", "NETFLIX"],
            channel: "Subscription",
            baseConfidence: 0.99
        ),
        CuratedMerchantEntry(
            canonicalName: "Apple Services",
            category: .streamingSubscriptions,
            aliases: ["APPLE.COM/BILL", "ITUNES.COM/BILL", "APPLE SUBSCRIPTIONS"],
            channel: "Digital",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Stan",
            category: .streamingSubscriptions,
            aliases: ["STAN.COM.AU", "STREAMCO MEDIA", "STAN AUSTRALIA", "STAN"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Kayo Sports",
            category: .streamingSubscriptions,
            aliases: ["KAYO SPORTS", "KAYO.COM.AU", "KAYOSPORTS"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "BINGE",
            category: .streamingSubscriptions,
            aliases: ["BINGE.COM.AU", "STREAMOTION BINGE", "BINGE"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Amazon Prime",
            category: .streamingSubscriptions,
            aliases: ["AMZNPRIME", "AMAZON PRIME", "PRIME VIDEO"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Disney+",
            category: .streamingSubscriptions,
            aliases: ["DISNEY PLUS", "DISNEY+", "DISNEYPLUS"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "YouTube Premium",
            category: .streamingSubscriptions,
            aliases: ["GOOGLE *YOUTUBE", "YOUTUBE PREMIUM", "YOUTUBE.COM/BILL"],
            channel: "Subscription",
            baseConfidence: 0.98
        ),

        // Telco & Internet Utilities
        CuratedMerchantEntry(
            canonicalName: "Telstra",
            category: .mobilePhone,
            aliases: ["TELSTRA CORPORATION", "TELSTRA PREPAID", "TELSTRA MOBILE", "TELSTRA"],
            channel: "Telco",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Optus",
            category: .mobilePhone,
            aliases: ["SINGTEL OPTUS", "OPTUS PREPAID", "OPTUS BILL", "OPTUS"],
            channel: "Telco",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Vodafone",
            category: .mobilePhone,
            aliases: ["VODAFONE AUSTRALIA", "TPG VODAFONE", "VODAFONE"],
            channel: "Telco",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Aussie Broadband",
            category: .utilitiesAndInternet,
            aliases: ["AUSSIE BROADBAND", "ABB NBN"],
            channel: "Internet",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Belong",
            category: .mobilePhone,
            aliases: ["BELONG MOBILE", "BELONG BROADBAND", "BELONG"],
            channel: "Telco",
            baseConfidence: 0.96
        ),

        // Energy & Water Utilities
        CuratedMerchantEntry(
            canonicalName: "Origin Energy",
            category: .utilitiesAndInternet,
            aliases: ["ORIGIN ENERGY", "ORIGIN ELECTRICITY", "ORIGIN GAS"],
            channel: "Energy",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "AGL Energy",
            category: .utilitiesAndInternet,
            aliases: ["AGL ELECTRICITY", "AGL ENERGY", "AGL SALES", "AGL "],
            channel: "Energy",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "EnergyAustralia",
            category: .utilitiesAndInternet,
            aliases: ["ENERGYAUSTRALIA", "ENERGY AUSTRALIA"],
            channel: "Energy",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Sydney Water",
            category: .utilitiesAndInternet,
            aliases: ["SYDNEY WATER CORP", "SYDNEY WATER"],
            channel: "Water",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Yarra Valley Water",
            category: .utilitiesAndInternet,
            aliases: ["YARRA VALLEY WATER", "YVW "],
            channel: "Water",
            baseConfidence: 0.98
        ),

        // Retail & Department Stores
        CuratedMerchantEntry(
            canonicalName: "Bunnings",
            category: .shoppingRetail,
            aliases: ["BUNNINGS WAREHOUSE", "BUNNINGS GROUP", "BUNNINGS"],
            channel: nil,
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Kmart",
            category: .shoppingRetail,
            aliases: ["KMART AUSTRALIA", "KMART TYRE", "KMART "],
            channel: nil,
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Target",
            category: .shoppingRetail,
            aliases: ["TARGET AUSTRALIA", "TARGET AU", "TARGET "],
            channel: nil,
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "JB Hi-Fi",
            category: .shoppingRetail,
            aliases: ["JB HI-FI GROUP", "JB HI FI", "JB HIFI", "JB HI-FI"],
            channel: nil,
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Officeworks",
            category: .shoppingRetail,
            aliases: ["OFFICEWORKS SUPERSTORES", "OFFICEWORKS"],
            channel: nil,
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "The Iconic",
            category: .shoppingRetail,
            aliases: ["THE ICONIC SYDNEY", "THE ICONIC ONLINE", "THE ICONIC"],
            channel: "Online",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Myer",
            category: .shoppingRetail,
            aliases: ["MYER STORES", "MYER PTY LTD", "MYER"],
            channel: nil,
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "David Jones",
            category: .shoppingRetail,
            aliases: ["DAVID JONES PTY", "DAVID JONES"],
            channel: nil,
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "Dan Murphy's",
            category: .groceries,
            aliases: ["DAN MURPHYS", "DAN MURPHY'S"],
            channel: "Liquor",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "BWS",
            category: .groceries,
            aliases: ["BWS BEER WINE SPIRITS", "BWS "],
            channel: "Liquor",
            baseConfidence: 0.96
        ),

        // Pharmacies & Healthcare
        CuratedMerchantEntry(
            canonicalName: "Chemist Warehouse",
            category: .healthcareMedicare,
            aliases: ["CHEMIST WAREHOUSE", "CHEMIST WHSE", "CW PHARMACY"],
            channel: "Pharmacy",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Priceline Pharmacy",
            category: .healthcareMedicare,
            aliases: ["PRICELINE PHARMACY", "PRICELINE"],
            channel: "Pharmacy",
            baseConfidence: 0.96
        ),
        CuratedMerchantEntry(
            canonicalName: "Medicare Australia",
            category: .healthcareMedicare,
            aliases: ["MEDICARE AUSTRALIA", "MEDICARE BENEFITS", "MEDICARE REBATE", "SERVICES AUST MEDICARE"],
            channel: "Government Rebate",
            baseConfidence: 0.98
        ),

        // Insurance & Financial
        CuratedMerchantEntry(
            canonicalName: "Medibank",
            category: .insurance,
            aliases: ["MEDIBANK PRIVATE", "MEDIBANK HEALTH", "MEDIBANK"],
            channel: "Health Insurance",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Bupa",
            category: .insurance,
            aliases: ["BUPA HI PTY", "BUPA AUSTRALIA", "BUPA HEALTH", "BUPA"],
            channel: "Health Insurance",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "NRMA Insurance",
            category: .insurance,
            aliases: ["NRMA INSURANCE", "NRMA MOTOR", "NRMA "],
            channel: "Insurance",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "AAMI",
            category: .insurance,
            aliases: ["AAMI INSURANCE", "AAMI DIRECT", "AAMI "],
            channel: "Insurance",
            baseConfidence: 0.97
        ),

        // Gyms & Fitness
        CuratedMerchantEntry(
            canonicalName: "Anytime Fitness",
            category: .gymFitness,
            aliases: ["ANYTIME FITNESS", "ANYTIME FIT"],
            channel: "Gym",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "Fitness First",
            category: .gymFitness,
            aliases: ["FITNESS FIRST AUSTRALIA", "FITNESS FIRST"],
            channel: "Gym",
            baseConfidence: 0.97
        ),
        CuratedMerchantEntry(
            canonicalName: "F45 Training",
            category: .gymFitness,
            aliases: ["F45 TRAINING", "F45 "],
            channel: "Fitness Studio",
            baseConfidence: 0.96
        ),

        // Buy Now Pay Later
        CuratedMerchantEntry(
            canonicalName: "Afterpay",
            category: .buyNowPayLater,
            aliases: ["AFTERPAY AUSTRALIA", "AFTERPAY PAYMENTS", "AFTERPAY"],
            channel: "BNPL",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Zip",
            category: .buyNowPayLater,
            aliases: ["ZIP PAY", "ZIP MONEY", "ZIP CO", "ZIP PAYMENTS"],
            channel: "BNPL",
            baseConfidence: 0.98
        ),

        // Government & Tax
        CuratedMerchantEntry(
            canonicalName: "Australian Taxation Office",
            category: .hecsHelp,
            aliases: ["AUSTRALIAN TAXATION OFFICE", "ATO HECS", "ATO HELP", "ATO PAYMENT"],
            channel: "Government",
            baseConfidence: 0.98
        ),
        CuratedMerchantEntry(
            canonicalName: "Services Australia",
            category: .governmentPayments,
            aliases: ["SERVICES AUSTRALIA", "CENTRELINK", "CENTRELINK FTB", "CENTRELINK DSP"],
            channel: "Government Income",
            baseConfidence: 0.98
        )
    ]

    // MARK: - Primary Normalisation Pipeline

    /// Normalises raw bank descriptions into high-quality recognized merchants.
    public func recognise(_ rawDescription: String) -> RecognizedMerchant {
        recognize(rawDescription: rawDescription)
    }

    public func recognise(rawDescription: String) -> RecognizedMerchant {
        recognize(rawDescription: rawDescription)
    }

    public func recognize(rawDescription: String) -> RecognizedMerchant {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RecognizedMerchant(
                canonicalName: "Unclassified Transaction",
                rawDescription: rawDescription,
                defaultCategory: nil,
                isKnownMerchant: false,
                confidence: 0.30
            )
        }

        // 1. Strip payment rail prefixes
        var cleaned = stripPaymentPrefixes(from: trimmed)

        // 2. Extract potential terminal/store ID and location suffixes
        let extractedMetadata = extractMetadataSuffixes(from: cleaned)
        cleaned = extractedMetadata.cleanedBase

        let upper = cleaned.uppercased()

        // 3. Match against curated directory (exact and alias matches)
        // Prefer longer alias matches first to prevent "Coles" from matching "Coles Express"
        let sortedEntries = Self.curatedDirectory.sorted { entryA, entryB in
            let maxLenA = entryA.aliases.map(\.count).max() ?? 0
            let maxLenB = entryB.aliases.map(\.count).max() ?? 0
            return maxLenA > maxLenB
        }

        for entry in sortedEntries {
            for alias in entry.aliases {
                if matchesAlias(upper: upper, alias: alias) {
                    return RecognizedMerchant(
                        canonicalName: entry.canonicalName,
                        rawDescription: rawDescription,
                        defaultCategory: entry.category,
                        isKnownMerchant: true,
                        confidence: entry.baseConfidence,
                        detectedTerminalId: extractedMetadata.terminalId,
                        detectedLocation: extractedMetadata.location,
                        channel: entry.channel
                    )
                }
            }
        }

        // 4. Fallback for unrecognized merchant: clean casing and format
        let fallbackName = formatFallbackDisplayName(cleaned)
        return RecognizedMerchant(
            canonicalName: fallbackName,
            rawDescription: rawDescription,
            defaultCategory: nil,
            isKnownMerchant: false,
            confidence: 0.50,
            detectedTerminalId: extractedMetadata.terminalId,
            detectedLocation: extractedMetadata.location,
            channel: nil
        )
    }

    // MARK: - Helper Methods

    private func stripPaymentPrefixes(from text: String) -> String {
        var current = text
        var stripped = true
        while stripped {
            stripped = false
            for prefix in Self.paymentPrefixes {
                if current.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                    current = String(current.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    stripped = true
                    break
                }
            }
        }
        return current.isEmpty ? text : current
    }

    private struct MetadataExtraction {
        let cleanedBase: String
        let terminalId: String?
        let location: String?
    }

    private func extractMetadataSuffixes(from text: String) -> MetadataExtraction {
        var tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var terminalId: String?
        var location: String?

        // Check trailing tokens for terminal IDs and location codes
        while tokens.count > 1 {
            let lastToken = tokens.last!.uppercased()

            // Check if last token is an Australian location code (e.g. "SYD", "NSW", "AU")
            if Self.australianLocationTokens.contains(lastToken) {
                location = lastToken
                tokens.removeLast()
                continue
            }

            // Check if last token is a numeric terminal/store number (e.g. "0321", "1234", "9901")
            if lastToken.count >= 2 && lastToken.count <= 6 && lastToken.allSatisfy(\.isNumber) {
                terminalId = lastToken
                tokens.removeLast()
                continue
            }

            // Check if last token is store pattern (e.g. "#102", "STN410")
            if lastToken.hasPrefix("#") && lastToken.dropFirst().allSatisfy(\.isNumber) {
                terminalId = String(lastToken.dropFirst())
                tokens.removeLast()
                continue
            }

            // Check domain suffixes like ".COM.AU" or ".COM"
            if lastToken.hasSuffix(".COM.AU") || lastToken.hasSuffix(".COM") {
                // Keep the token but strip the domain extension for cleaner merchant naming
                let stripped = tokens.last!
                    .replacingOccurrences(of: ".com.au", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: ".com", with: "", options: .caseInsensitive)
                tokens[tokens.count - 1] = stripped
            }

            break
        }

        let cleaned = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return MetadataExtraction(
            cleanedBase: cleaned.isEmpty ? text : cleaned,
            terminalId: terminalId,
            location: location
        )
    }

    private func matchesAlias(upper: String, alias: String) -> Bool {
        if upper == alias { return true }
        if upper.hasPrefix(alias + " ") { return true }
        if upper.hasSuffix(" " + alias) { return true }
        if upper.contains(" " + alias + " ") { return true }
        // Handle asterisks (e.g. "UBER *TRIP")
        if alias.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: alias).replacingOccurrences(of: "\\*", with: "\\s*\\*?\\s*")
            if let regex = try? NSRegularExpression(pattern: "\\b" + escaped, options: .caseInsensitive) {
                let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
                if regex.firstMatch(in: upper, range: range) != nil {
                    return true
                }
            }
        }
        return false
    }

    private func formatFallbackDisplayName(_ text: String) -> String {
        // Strip common trailing transaction punctuation & clean casing
        let cleaned = text
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return text }

        // If the string is all uppercase or all lowercase, capitalize each word nicely
        if cleaned == cleaned.uppercased() || cleaned == cleaned.lowercased() {
            return words.map { word -> String in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }
        return cleaned
    }
}
