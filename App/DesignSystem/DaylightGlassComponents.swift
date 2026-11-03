import SwiftUI

// MARK: - Reusable Atmospheric Emerald Background

/// A native SwiftUI background featuring a deep forest/emerald gradient base in dark mode,
/// or a warm cream/beige atmospheric gradient with subtle blush and soft-red lighting in light mode.
public struct DaylightAtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateGlow: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { _ in
            ZStack {
                if colorScheme == .dark {
                    // Deep dark base gradient (#071C13 -> #0B2A1D)
                    LinearGradient(
                        colors: [
                            DaylightTheme.Emerald.forest,
                            DaylightTheme.Emerald.dark,
                            Color(red: 6/255, green: 22/255, blue: 15/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Top-Trailing soft radial lime glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DaylightTheme.Lime.primary.opacity(0.18),
                                    DaylightTheme.Emerald.secondary.opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 240
                            )
                        )
                        .frame(width: 480, height: 480)
                        .blur(radius: 60)
                        .offset(x: 160, y: -200)

                    // Bottom-Leading subtle emerald/mint lighting
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DaylightTheme.Lime.mint.opacity(0.12),
                                    DaylightTheme.Emerald.secondary.opacity(0.20),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 280
                            )
                        )
                        .frame(width: 520, height: 520)
                        .blur(radius: 80)
                        .offset(x: -180, y: 340)
                } else {
                    // Light theme direction: warm cream and beige with restrained blush accents
                    LinearGradient(
                        colors: [
                            DaylightTheme.lightCanvas,
                            DaylightTheme.lightCream,
                            DaylightTheme.lightBeige,
                            DaylightTheme.lightBlush,
                            DaylightTheme.lightCream
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Top-Trailing soft blush ambient lighting
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DaylightTheme.lightBlush.opacity(0.30),
                                    DaylightTheme.lightSoftRed.opacity(0.10),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 240
                            )
                        )
                        .frame(width: 480, height: 480)
                        .blur(radius: 60)
                        .offset(x: 160, y: -200)

                    // Bottom-Leading subtle beige and soft-red warmth
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DaylightTheme.lightBeige.opacity(0.28),
                                    DaylightTheme.lightSoftRed.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 280
                            )
                        )
                        .frame(width: 520, height: 520)
                        .blur(radius: 80)
                        .offset(x: -180, y: 340)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reusable Glass Card Component

/// A translucent frosted-glass container with subtle 1pt border and soft shadow.
public struct DaylightGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let isElevated: Bool
    private let content: Content

    public init(
        padding: CGFloat = DaylightTheme.Spacing.cardPadding,
        cornerRadius: CGFloat = DaylightTheme.Radius.card,
        isElevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.isElevated = isElevated
        self.content = content()
    }

    private var cardFillColor: Color {
        if colorScheme == .dark {
            return isElevated ? Color.white.opacity(0.12) : Color.white.opacity(0.08)
        } else {
            return isElevated ? DaylightTheme.lightCreamElevated : DaylightTheme.lightCream.opacity(0.94)
        }
    }

    private var cardStrokeColor: Color {
        if colorScheme == .dark {
            return isElevated ? DaylightTheme.Glass.borderHighlight : DaylightTheme.Glass.border
        } else {
            return isElevated ? Color(red: 14/255, green: 104/255, blue: 56/255).opacity(0.18) : Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.09)
        }
    }

    private var cardShadowColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(isElevated ? 0.35 : 0.20)
        } else {
            return Color(red: 7/255, green: 28/255, blue: 19/255).opacity(isElevated ? 0.08 : 0.04)
        }
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(cardFillColor)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.65 : 0.78))
                            .opacity(reduceTransparency ? 0 : 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.white.opacity(0.62),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: cardShadowColor,
                radius: isElevated ? 16 : 8,
                x: 0,
                y: isElevated ? 6 : 2
            )
    }
}

// MARK: - Reusable Glass Action Button

/// A frosted-glass pill or rounded action button with press animation.
public struct DaylightGlassButton: View {
    public enum Style {
        case primaryLime
        case glassSecondary
        case glassSubtle
    }

    @Environment(\.colorScheme) private var colorScheme
    private let title: String
    private let icon: String?
    private let style: Style
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primaryLime,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(DaylightTypography.captionMedium)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(backgroundView)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primaryLime:
            return DaylightTheme.Emerald.forest // Dark forest green text on lime (13.8:1 contrast in both modes)
        case .glassSecondary:
            return colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
        case .glassSubtle:
            return DaylightTheme.textPrimary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primaryLime:
            DaylightTheme.Lime.primary
        case .glassSecondary:
            (colorScheme == .dark ? DaylightTheme.Glass.elevated : DaylightTheme.lightCreamElevated)
                .background(.ultraThinMaterial.opacity(0.70))
        case .glassSubtle:
            (colorScheme == .dark ? DaylightTheme.Glass.translucent : DaylightTheme.lightCream.opacity(0.85))
                .background(.ultraThinMaterial.opacity(0.50))
        }
    }

    private var borderColor: Color {
        switch style {
        case .primaryLime:
            return DaylightTheme.Lime.soft
        case .glassSecondary:
            return colorScheme == .dark ? DaylightTheme.Lime.primary.opacity(0.30) : DaylightTheme.accentEmerald.opacity(0.25)
        case .glassSubtle:
            return DaylightTheme.Glass.border
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primaryLime:
            return colorScheme == .dark ? DaylightTheme.Lime.glow : Color.black.opacity(0.08)
        case .glassSecondary, .glassSubtle:
            return colorScheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.05)
        }
    }
}

// MARK: - Reusable Circular Glass Icon Button

/// A 44x44 circular translucent glass button for header controls and actions.
public struct DaylightGlassIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    private let icon: String
    private let badgeCount: Int
    private let action: () -> Void

    public init(
        icon: String,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.badgeCount = badgeCount
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DaylightTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? DaylightTheme.Glass.translucent : DaylightTheme.lightCream.opacity(0.92))
                            .background(Circle().fill(.ultraThinMaterial.opacity(0.60)))
                    )
                    .overlay(
                        Circle()
                            .stroke(DaylightTheme.Glass.border, lineWidth: 1)
                    )

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DaylightTheme.Emerald.forest)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DaylightTheme.Lime.primary))
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Animated Waveform View

/// A native animated audio waveform visualizer for voice and assistant interactions.
public struct DaylightWaveformView: View {
    public let isAnimating: Bool
    public let barCount: Int

    @State private var phase: CGFloat = 0

    public init(isAnimating: Bool = true, barCount: Int = 24) {
        self.isAnimating = isAnimating
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    totalBars: barCount,
                    isAnimating: isAnimating,
                    phase: phase
                )
            }
        }
        .frame(height: 60)
        .onAppear {
            if isAnimating {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let totalBars: Int
    let isAnimating: Bool
    let phase: CGFloat

    private var normalizedHeight: CGFloat {
        guard isAnimating else { return 8 }
        let progress = CGFloat(index) / CGFloat(totalBars)
        let wave = sin((progress * .pi * 2) + (phase * .pi))
        let centerWeight = 1.0 - abs(progress - 0.5) * 1.6
        let calculated = 8 + (max(0, centerWeight) * 44 * CGFloat(abs(wave)))
        return max(6, calculated)
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark ? [
                        DaylightTheme.Lime.primary,
                        DaylightTheme.Lime.mint
                    ] : [
                        DaylightTheme.accentEmerald,
                        Color(red: 43/255, green: 182/255, blue: 115/255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3.5, height: normalizedHeight)
            .animation(.easeInOut(duration: 0.25).delay(Double(index) * 0.02), value: phase)
    }
}

// MARK: - View Modifiers for Glassmorphism

public extension View {
    /// Applies the full-bleed atmospheric emerald background.
    func daylightGlassBackground() -> some View {
        ZStack {
            DaylightAtmosphericBackground()
            self
        }
    }
}
