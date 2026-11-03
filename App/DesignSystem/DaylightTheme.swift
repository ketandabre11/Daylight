import SwiftUI

// MARK: - Brand Configuration

/// Centralised brand configuration so the product name and tagline can be updated
/// without modifying application architecture.
public enum BrandConfig {
    public static let appName = "Daylight"
    public static let tagline = "Know what you can spend today, understand where your money goes, and feel in control of your finances."
    public static let supportEmail = "support@daylightmoney.com.au"
    public static let regulatoryDisclaimer = "Daylight is a personal finance and budgeting companion, not a bank, Authorised Deposit-taking Institution (ADI), lender, tax agent, or licensed financial adviser. Figures shown are budgeting estimates and do not represent general or personal financial advice under the Corporations Act 2001 (Cth)."
}

// MARK: - App Theme Mode

public enum AppThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Semantic Design Tokens

public enum DaylightTheme {
    #if canImport(UIKit)
    public static func dynamicColor(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
    #else
    public static func dynamicColor(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
    }
    #endif

    // MARK: - Core Palette Definitions

    public enum Emerald {
        /// Deep forest green: #071C13
        public static let forest = Color(red: 7/255, green: 28/255, blue: 19/255)
        /// Dark emerald base: #0B2A1D
        public static let dark = Color(red: 11/255, green: 42/255, blue: 29/255)
        /// Secondary emerald: #123C2B
        public static let secondary = Color(red: 18/255, green: 60/255, blue: 43/255)
        /// Vibrant deep emerald for light mode text/accents (#0E6838)
        public static let vibrant = Color(red: 14/255, green: 104/255, blue: 56/255)
        /// Deep emerald gradient background
        public static var backgroundGradient: LinearGradient {
            LinearGradient(
                colors: [forest, dark, Color(red: 9/255, green: 34/255, blue: 23/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    public enum Lime {
        /// Vibrant lime accent: #C2F36B (Used for fills and dark mode highlights)
        public static let primary = Color(red: 194/255, green: 243/255, blue: 107/255)
        /// Soft lime: #A9DE63
        public static let soft = Color(red: 169/255, green: 222/255, blue: 99/255)
        /// Mint accent: #9BE5C7
        public static let mint = Color(red: 155/255, green: 229/255, blue: 199/255)
        /// Subtle lime glow
        public static let glow = primary.opacity(0.40)
    }

    // Warm light-mode surfaces
    public static let lightCream = Color(red: 255/255, green: 249/255, blue: 239/255)
    public static let lightCreamElevated = Color(red: 255/255, green: 252/255, blue: 246/255)
    public static let lightCreamSecondary = Color(red: 252/255, green: 244/255, blue: 229/255)
    public static let lightBeige = Color(red: 243/255, green: 231/255, blue: 214/255)
    public static let lightBlush = Color(red: 252/255, green: 237/255, blue: 233/255)
    public static let lightSoftRed = Color(red: 245/255, green: 215/255, blue: 208/255)
    public static let lightCanvas = Color(red: 248/255, green: 243/255, blue: 235/255)
    public static let lightCanvasSecondary = Color(red: 241/255, green: 233/255, blue: 222/255)

    // MARK: - Adaptive Semantic Tokens (WCAG AA Compliant in both appearances)

    /// Deep emerald for light-theme text/icons/borders (contrast > 6.8:1); Lime for dark-theme.
    public static let accentEmerald = Color(red: 14/255, green: 104/255, blue: 56/255)
    public static let accentLime = Lime.primary

    /// Primary accent: Emerald in Light, Lime in Dark
    public static var accent: Color {
        dynamicColor(light: accentEmerald, dark: Lime.primary)
    }
    public static var accentText: Color {
        dynamicColor(light: accentEmerald, dark: Lime.primary)
    }
    public static var primaryAction: Color {
        dynamicColor(light: accentEmerald, dark: Lime.primary)
    }

    /// Primary label color: Deep Forest Green (#071C13) in Light (17.7:1 AAA), Pure White in Dark (18.7:1 AAA)
    public static var textPrimary: Color {
        dynamicColor(light: Emerald.forest, dark: Color.white)
    }

    /// Secondary label color: Slate Forest (#2C4F3F) in Light (9.1:1 AAA), Translucent White in Dark (9.1:1 AAA)
    public static var textSecondary: Color {
        dynamicColor(light: Color(red: 44/255, green: 79/255, blue: 63/255), dark: Color.white.opacity(0.72))
    }

    /// Muted tertiary label color: Sage Forest (#4D705F) in Light (5.5:1 AA), Translucent White in Dark (5.8:1 AA)
    public static var textMuted: Color {
        dynamicColor(light: Color(red: 77/255, green: 112/255, blue: 95/255), dark: Color.white.opacity(0.48))
    }

    /// Base canvas background: Warm ivory in Light, Deep Forest (#071C13) in Dark
    public static var canvasBackground: Color {
        dynamicColor(light: lightCanvas, dark: Emerald.forest)
    }

    /// Grouped card surface: Warm cream in Light, Frosted Glass (white 0.08) in Dark
    public static var surface: Color {
        dynamicColor(light: lightCream, dark: Color.white.opacity(0.08))
    }

    /// Elevated surface: Light cream in Light, Elevated Frosted Glass in Dark
    public static var surfaceElevated: Color {
        dynamicColor(light: lightCreamElevated, dark: Color.white.opacity(0.12))
    }

    /// Hairline glass border
    public static var glassBorder: Color {
        dynamicColor(light: Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.10), dark: Color.white.opacity(0.16))
    }

    /// Elevated border highlight
    public static var glassBorderHighlight: Color {
        dynamicColor(light: accentEmerald.opacity(0.20), dark: Color.white.opacity(0.28))
    }

    /// Hairline divider
    public static var dividerColor: Color {
        dynamicColor(light: Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.08), dark: Color.white.opacity(0.12))
    }

    /// Forest green for labels and brand text (never raw neon lime in light mode)
    public static var forestGreen: Color {
        dynamicColor(light: Emerald.forest, dark: Lime.primary)
    }

    public enum Glass {
        public static var translucent: Color { DaylightTheme.surface }
        public static var elevated: Color { DaylightTheme.surfaceElevated }
        public static var border: Color { DaylightTheme.glassBorder }
        public static var borderHighlight: Color { DaylightTheme.glassBorderHighlight }
        public static let cornerRadius: CGFloat = 20
    }

    public enum GlassText {
        public static var primary: Color { DaylightTheme.textPrimary }
        public static var secondary: Color { DaylightTheme.textSecondary }
        public static var muted: Color { DaylightTheme.textMuted }
    }

    // Canvas & Backgrounds (Explicit ColorScheme helpers for backwards compatibility)
    public static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Emerald.forest : lightCanvas
    }
    public static func backgroundPrimary(for scheme: ColorScheme) -> Color {
        background(for: scheme)
    }
    public static func backgroundSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Emerald.dark : lightCanvasSecondary
    }

    // Grouped Card Surfaces
    public static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : lightCream
    }
    public static func surfacePrimary(for scheme: ColorScheme) -> Color {
        surface(for: scheme)
    }
    public static func secondarySurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : lightCreamSecondary
    }
    public static func surfaceSecondary(for scheme: ColorScheme) -> Color {
        secondarySurface(for: scheme)
    }
    public static func surfaceTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Emerald.secondary.opacity(0.40) : Color(red: 228/255, green: 236/255, blue: 231/255)
    }

    // Text & Labels
    public static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Emerald.forest
    }
    public static func textPrimary(for scheme: ColorScheme) -> Color {
        primaryText(for: scheme)
    }
    public static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.72) : Color(red: 44/255, green: 79/255, blue: 63/255)
    }
    public static func textSecondary(for scheme: ColorScheme) -> Color {
        secondaryText(for: scheme)
    }
    public static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.48) : Color(red: 77/255, green: 112/255, blue: 95/255)
    }

    // Borders & Separators
    public static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.10)
    }
    public static func borderPrimary(for scheme: ColorScheme) -> Color {
        border(for: scheme)
    }
    public static func separator(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.08)
    }

    // Brand & Semantic Palette
    public static let accentBright = Lime.soft

    /// Mint container for secondary highlights.
    public static let sageAccent = Lime.mint
    public static func sageSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 235/255, green: 245/255, blue: 239/255)
    }

    /// Financially positive state (accessible green).
    public static var positive: Color {
        dynamicColor(light: Color(red: 14/255, green: 104/255, blue: 56/255), dark: Color(red: 52/255, green: 211/255, blue: 153/255))
    }
    public static func positiveSurface(for scheme: ColorScheme) -> Color {
        positive.opacity(scheme == .dark ? 0.22 : 0.12)
    }

    /// Accessible caution/warning state (amber).
    public static var warning: Color {
        dynamicColor(light: Color(red: 180/255, green: 83/255, blue: 9/255), dark: Color(red: 251/255, green: 191/255, blue: 36/255))
    }
    public static func warningSurface(for scheme: ColorScheme) -> Color {
        warning.opacity(scheme == .dark ? 0.22 : 0.12)
    }

    /// Accessible destructive/over-budget state (red).
    public static var cautionRed: Color {
        dynamicColor(light: Color(red: 197/255, green: 34/255, blue: 31/255), dark: Color(red: 248/255, green: 113/255, blue: 113/255))
    }
    public static var negative: Color { cautionRed }
    public static func negativeSurface(for scheme: ColorScheme) -> Color {
        cautionRed.opacity(scheme == .dark ? 0.22 : 0.12)
    }

    /// Disabled UI control state.
    public static let disabled = Color.secondary.opacity(0.40)

    /// Standard accessible touch-target height for primary/secondary buttons.
    public static let buttonHeight: CGFloat = 50

    /// Unified 4-point spacing scale and layout tokens
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let base: CGFloat = 20
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 40

        /// Standard horizontal screen margin across the entire application
        public static let screenMargin: CGFloat = 16
        /// Standard internal card padding
        public static let cardPadding: CGFloat = 16
        /// Standard vertical gap between stacked cards
        public static let cardGap: CGFloat = 16
        /// Standard bottom safe inset to prevent floating navigation bar overlap
        public static let bottomNavInset: CGFloat = 88
    }

    /// Corner radii scale
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 16
        public static let card: CGFloat = 20
        public static let lg: CGFloat = 24
        public static let pill: CGFloat = 999
    }

    /// Icon dimensions
    public enum IconSize {
        public static let sm: CGFloat = 16
        public static let md: CGFloat = 20
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
    }
}

// MARK: - Centralised Semantic Typography System

public enum DaylightTypography {
    /// Large financial dashboard values ($133.33)
    public static let largeDisplay = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// Main screen headings
    public static let screenTitle = Font.title2.weight(.bold)

    /// Section titles
    public static let sectionTitle = Font.headline.weight(.semibold)

    /// Card and component headings
    public static let cardTitle = Font.subheadline.weight(.semibold)

    /// Main descriptions and content
    public static let body = Font.body
    public static let bodyMedium = Font.body.weight(.medium)

    /// Supporting / callout information
    public static let callout = Font.callout
    public static let calloutMedium = Font.callout.weight(.medium)
    public static let subheadline = Font.subheadline
    public static let subheadlineMedium = Font.subheadline.weight(.medium)

    /// Dates, hints and metadata
    public static let caption = Font.caption
    public static let captionMedium = Font.caption.weight(.medium)

    /// Compact transaction-list hierarchy
    public static let transactionTitle = Font.subheadline.weight(.medium)
    public static let transactionMetadata = Font.caption
    public static let transactionAmount = Font.subheadline.weight(.bold).monospacedDigit()

    /// Legal and supplementary fine print
    public static let finePrint = Font.caption2

    /// Monospaced rounded currency amounts
    public static func financialAmount(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Reusable Surface Card

public struct DaylightCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = DaylightTheme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .fill(DaylightTheme.surface(for: colorScheme))
                    .background(
                        Group {
                            if !reduceTransparency {
                                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.65 : 0.75))
                            }
                        }
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .strokeBorder(DaylightTheme.border(for: colorScheme), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.white.opacity(0.62),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.035),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}

// MARK: - Semantic Status Badge (Never relies on colour alone; pairs icon + label)

public enum FinancialBadgeTone: Sendable {
    case positive
    case warning
    case overBudget
    case neutral
    case demo
}

public struct DaylightBadge: View {
    let text: String
    let icon: String
    let tone: FinancialBadgeTone

    public init(_ text: String, icon: String, tone: FinancialBadgeTone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    private var foregroundColor: Color {
        switch tone {
        case .positive: return DaylightTheme.positive
        case .warning: return DaylightTheme.warning
        case .overBudget: return DaylightTheme.cautionRed
        case .neutral: return DaylightTheme.accent
        case .demo: return Color.purple
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor)
        .background(
            Capsule(style: .continuous)
                .fill(foregroundColor.opacity(0.13))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Progress Ring for Daily Allowance

public struct AllowanceRingView: View {
    let progress: Double
    let isOverAllowance: Bool
    let centerTitle: String
    let centerAmount: String
    let subtitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: Double,
        isOverAllowance: Bool,
        centerTitle: String,
        centerAmount: String,
        subtitle: String
    ) {
        self.progress = min(max(progress, 0), 1.0)
        self.isOverAllowance = isOverAllowance
        self.centerTitle = centerTitle
        self.centerAmount = centerAmount
        self.subtitle = subtitle
    }

    private var ringColor: Color {
        if isOverAllowance {
            return DaylightTheme.cautionRed
        } else if progress > 0.80 {
            return DaylightTheme.warning
        } else {
            return DaylightTheme.positive
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: progress)

            VStack(spacing: 4) {
                Text(centerTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(centerAmount)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Image(systemName: isOverAllowance ? "info.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(ringColor)
            }
            .padding(.horizontal, 16)
        }
        .frame(width: 176, height: 176)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centerTitle): \(centerAmount). \(subtitle)")
    }
}

// MARK: - Empty State Component

public struct DaylightEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        DaylightCard(padding: DaylightTheme.Spacing.lg) {
            VStack(spacing: DaylightTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(DaylightTheme.accent)
                    .padding(.bottom, 4)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DaylightTheme.accent)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Section Header

public struct DaylightSectionHeader: View {
    let title: String
    let subtitle: String?
    let trailingTitle: String?
    let trailingAction: (() -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        trailingTitle: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DaylightTheme.accent)
            }
        }
    }
}

// MARK: - Daylight Brand Mark & Reusable Action Button Styles

public struct DaylightBrandMarkView: View {
    let size: CGFloat

    public init(size: CGFloat = 68) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DaylightTheme.forestGreen, DaylightTheme.sageAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: DaylightTheme.forestGreen.opacity(0.22), radius: 12, x: 0, y: 6)

            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

public struct DaylightPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(
                colorScheme == .dark ? DaylightTheme.Emerald.forest : Color.white
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: DaylightTheme.buttonHeight)
            .padding(.horizontal, DaylightTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .fill(
                        isEnabled
                            ? (colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald)
                            : DaylightTheme.disabled
                    )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

public struct DaylightSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(isEnabled ? DaylightTheme.primaryText(for: colorScheme) : .secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DaylightTheme.buttonHeight)
            .padding(.horizontal, DaylightTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .fill(DaylightTheme.sageSurface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .strokeBorder(DaylightTheme.sageAccent.opacity(0.38), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.86 : 1.0)
    }
}

// MARK: - Compact Dropdown Pill Label (Used Across All Screens)

public struct DaylightDropdownPill: View {
    let text: String
    let icon: String?
    let maxWidth: CGFloat?

    public init(_ text: String, icon: String? = nil, maxWidth: CGFloat? = 185) {
        self.text = text
        self.icon = icon
        self.maxWidth = maxWidth
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9.5, weight: .semibold))
                .opacity(0.85)
        }
        .foregroundStyle(DaylightTheme.forestGreen)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: maxWidth, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DaylightTheme.forestGreen.opacity(0.10))
        )
    }
}

// MARK: - Contextual Information Disclosure

public struct DaylightInfoDisclosure: View {
    private let message: LocalizedStringKey
    @State private var isExpanded = false

    public init(_ message: LocalizedStringKey) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DaylightTheme.Spacing.xs) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(DaylightTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(DaylightTheme.accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide information" : "Show information")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Standardized Destructive & Tertiary Button Styles

public struct DaylightDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DaylightTypography.sectionTitle)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DaylightTheme.buttonHeight)
            .padding(.horizontal, DaylightTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .fill(isEnabled ? DaylightTheme.cautionRed : DaylightTheme.cautionRed.opacity(0.40))
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

public struct DaylightTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DaylightTypography.cardTitle)
            .foregroundStyle(isEnabled ? DaylightTheme.accent : .secondary)
            .padding(.horizontal, DaylightTheme.Spacing.xs)
            .padding(.vertical, DaylightTheme.Spacing.xxs)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.70 : 1.0)
    }
}

// MARK: - Standardized Form Field Container

public struct DaylightFormFieldContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let helperText: String?
    let errorText: String?
    let content: Content

    public init(
        _ label: String,
        helperText: String? = nil,
        errorText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.helperText = helperText
        self.errorText = errorText
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DaylightTheme.Spacing.xxs) {
            Text(label)
                .font(DaylightTypography.captionMedium)
                .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))

            content

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.cautionRed)
            } else if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(DaylightTypography.finePrint)
                    .foregroundStyle(DaylightTheme.textTertiary(for: colorScheme))
            }
        }
    }
}

// MARK: - Standardized Text Field Modifier

public struct DaylightTextFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isError: Bool

    public init(isError: Bool = false) {
        self.isError = isError
    }

    public func body(content: Content) -> some View {
        content
            .font(DaylightTypography.body)
            .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
            .padding(.horizontal, DaylightTheme.Spacing.sm)
            .padding(.vertical, DaylightTheme.Spacing.sm)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm, style: .continuous)
                    .fill(DaylightTheme.secondarySurface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.sm, style: .continuous)
                    .strokeBorder(isError ? DaylightTheme.cautionRed : DaylightTheme.border(for: colorScheme), lineWidth: 1)
            )
    }
}

public extension View {
    func daylightTextFieldStyle(isError: Bool = false) -> some View {
        modifier(DaylightTextFieldModifier(isError: isError))
    }
}

// MARK: - Standardized Card Header

public struct DaylightCardHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let icon: String?

    public init(_ title: String, subtitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: DaylightTheme.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(DaylightTypography.cardTitle)
                    .foregroundStyle(DaylightTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DaylightTypography.cardTitle)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DaylightTypography.caption)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                }
            }
            Spacer()
        }
    }
}

// MARK: - Standardized List Row

public struct DaylightListRow<Leading: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: DaylightTheme.Spacing.sm) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DaylightTypography.cardTitle)
                    .foregroundStyle(DaylightTheme.primaryText(for: colorScheme))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DaylightTypography.caption)
                        .foregroundStyle(DaylightTheme.secondaryText(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer()

            trailing
        }
        .padding(.vertical, DaylightTheme.Spacing.xs)
    }
}
