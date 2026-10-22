import SwiftUI

// MARK: - Brand Configuration

/// Centralised brand configuration so the product name and tagline can be updated
/// without modifying application architecture.
public enum BrandConfig {
    public static let appName = "Daylight Money"
    public static let tagline = "Know what you can spend today, understand where your money goes, and feel in control of your finances."
    public static let supportEmail = "support@daylightmoney.com.au"
    public static let regulatoryDisclaimer = "Daylight Money is a personal finance and budgeting companion, not a bank, Authorised Deposit-taking Institution (ADI), lender, tax agent, or licensed financial adviser. Figures shown are budgeting estimates and do not represent general or personal financial advice under the Corporations Act 2001 (Cth)."
}

// MARK: - App Theme Mode

public enum AppThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Daylight (Light)"
        case .dark: return "Evening (Dark)"
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
    /// Warm stone/alabaster primary canvas in light mode (#F7F7F5), deep charcoal (#121316) in dark mode.
    public static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.075, blue: 0.086)
            : Color(red: 0.969, green: 0.969, blue: 0.961)
    }

    /// Elevated card surface (#FFFFFF in light mode, #1C1E24 in dark mode).
    public static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.118, blue: 0.141)
            : Color.white
    }

    /// Secondary grouped surface (#F0EFEA in light mode, #252830 in dark mode).
    public static func secondarySurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.145, green: 0.157, blue: 0.188)
            : Color(red: 0.941, green: 0.937, blue: 0.918)
    }

    /// Primary near-black text (#1D1D1F in light mode, #F5F5F7 in dark mode).
    public static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.96, green: 0.96, blue: 0.97)
            : Color(red: 0.114, green: 0.114, blue: 0.122)
    }

    /// Restrained secondary grey text with WCAG AA contrast.
    public static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.68, green: 0.70, blue: 0.74)
            : Color(red: 0.36, green: 0.37, blue: 0.40)
    }

    /// Subtle hairline border.
    public static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    /// Deep forest-green primary action color (#145C3D in light mode, #1E7D54 in dark mode).
    public static let forestGreen = Color(red: 0.078, green: 0.361, blue: 0.239)
    public static let primaryAction = forestGreen

    /// Muted sage secondary accent (#5F8270).
    public static let sageAccent = Color(red: 0.373, green: 0.510, blue: 0.439)

    /// Subtle muted sage container fill for secondary highlights.
    public static func sageSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.21, blue: 0.18)
            : Color(red: 0.914, green: 0.941, blue: 0.922)
    }

    /// Sophisticated Tasman Teal / Eucalyptus Blue accent (aligned with deep forest-sage palette).
    public static let accent = Color(red: 0.078, green: 0.380, blue: 0.275)
    public static let accentBright = Color(red: 0.11, green: 0.52, blue: 0.37)

    /// Accessible positive financial state (Forest Green).
    public static let positive = Color(red: 0.11, green: 0.53, blue: 0.33)

    /// Accessible caution/approaching threshold state (Warm Amber).
    public static let warning = Color(red: 0.78, green: 0.47, blue: 0.06)

    /// Restrained over-budget or alert state (Terracotta Red — empathetic, not harsh neon).
    public static let cautionRed = Color(red: 0.76, green: 0.23, blue: 0.22)

    /// Standard accessible touch-target height for primary/secondary buttons.
    public static let buttonHeight: CGFloat = 50

    /// Spacing scale
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    /// Corner radii
    public enum Radius {
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 22
    }
}

// MARK: - Reusable Surface Card

public struct DaylightCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
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
            )
            .overlay(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .strokeBorder(DaylightTheme.border(for: colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .clear : Color.black.opacity(0.035),
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
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DaylightTheme.buttonHeight)
            .padding(.horizontal, DaylightTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DaylightTheme.Radius.md, style: .continuous)
                    .fill(isEnabled ? DaylightTheme.forestGreen : DaylightTheme.sageAccent.opacity(0.45))
            )
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


