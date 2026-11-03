import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension Notification.Name {
    static let daylightScrollPositionChanged = Notification.Name("daylightScrollPositionChanged")
}

private struct DaylightScrollNavigationReporter: ViewModifier {
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            NotificationCenter.default.post(
                name: .daylightScrollPositionChanged,
                object: nil,
                userInfo: ["offset": offset]
            )
        }
    }
}

public extension View {
    func reportsDaylightScrollPosition() -> some View {
        modifier(DaylightScrollNavigationReporter())
    }
}

/// A floating native iOS translucent glass bottom navigation bar with a sliding selection highlight,
/// equal touch target distribution, and a prominent central AI Assistant action.
public struct DaylightGlassNavigationBar: View {
    @Binding public var selectedSection: AppNavigationSection
    @Binding public var isCompact: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navIndicatorNamespace

    @State private var activeIndicatorSection: AppNavigationSection = .overview

    public init(
        selectedSection: Binding<AppNavigationSection>,
        isCompact: Binding<Bool> = .constant(false)
    ) {
        self._selectedSection = selectedSection
        self._isCompact = isCompact
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 1. Home / Overview
            tabItem(
                section: .overview,
                title: "Home",
                icon: "sun.max.fill"
            )

            // 2. Transactions / Activity
            tabItem(
                section: .transactions,
                title: "Activity",
                icon: "list.bullet.rectangle.portrait.fill"
            )

            // 3. Central AI Assistant Action
            centerAssistantButton

            // 4. Budgets
            tabItem(
                section: .budgets,
                title: "Budgets",
                icon: "chart.pie.fill"
            )

            // 5. Savings
            tabItem(
                section: .savings,
                title: "Savings",
                icon: "target"
            )
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .frame(height: 48)
        .background(glassCapsuleBackground)
        .overlay(glassCapsuleBorder.allowsHitTesting(false))
        .shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.40)
                : Color(red: 7/255, green: 28/255, blue: 19/255).opacity(0.12),
            radius: 20,
            x: 0,
            y: 8
        )
        .padding(.horizontal, isCompact ? 42 : DaylightTheme.Spacing.screenMargin)
        .padding(.bottom, isCompact ? 2 : 6)
        .frame(height: isCompact ? 52 : 66)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bottom Navigation Bar")
        .onAppear {
            if isBarSection(selectedSection) {
                activeIndicatorSection = selectedSection
            }
        }
        .onChange(of: selectedSection) { _, newSection in
            if isBarSection(newSection) {
                let springAnimation: Animation = reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.35, dampingFraction: 0.78)
                withAnimation(springAnimation) {
                    activeIndicatorSection = newSection
                }
            }
        }
    }

    private func isBarSection(_ section: AppNavigationSection) -> Bool {
        section == .overview ||
        section == .transactions ||
        section == .assistant ||
        section == .budgets ||
        section == .savings
    }

    // MARK: - Tab Item with Sliding Highlight

    private func tabItem(section: AppNavigationSection, title: String, icon: String) -> some View {
        let isSelected = selectedSection == section || activeIndicatorSection == section
        let activeTint = colorScheme == .dark
            ? DaylightTheme.Lime.primary.opacity(0.16)
            : Color.white.opacity(0.38)
        let activeBorder = colorScheme == .dark
            ? Color.white.opacity(0.30)
            : DaylightTheme.accentEmerald.opacity(0.22)
        let activeHighlight = colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.72)
        let activeShadow = colorScheme == .dark
            ? Color.black.opacity(0.20)
            : DaylightTheme.accentEmerald.opacity(0.10)

        return Button {
            selectSection(section)
        } label: {
            ZStack {
                // Sliding Selection Highlight Capsule
                if activeIndicatorSection == section {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .fill(activeTint)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    activeBorder,
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    activeHighlight,
                                    lineWidth: 0.75
                                )
                                .padding(1)
                        )
                        .frame(height: isCompact ? 40 : 44)
                        .shadow(
                            color: activeShadow,
                            radius: 5,
                            y: 2
                        )
                        .matchedGeometryEffect(id: "nav_sliding_indicator", in: navIndicatorNamespace)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }

                // Tab Content (Centered Icon + Label)
                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(itemColor(isSelected: isSelected))
                        .frame(width: 20, height: 20)
                        .scaleEffect(isCompact ? 0.88 : 1)

                    Text(title)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(itemColor(isSelected: isSelected))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: 12)
                        .scaleEffect(isCompact ? 0.8 : 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Central Prominent AI Assistant Action

    private var centerAssistantButton: some View {
        let isSelected = selectedSection == .assistant || activeIndicatorSection == .assistant

        return Button {
            selectSection(.assistant)
        } label: {
            ZStack {
                // When Assistant is the active indicator target, the sliding indicator smoothly docks here
                if activeIndicatorSection == .assistant {
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? DaylightTheme.Lime.primary.opacity(0.25)
                                : DaylightTheme.accentEmerald.opacity(0.16)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    colorScheme == .dark
                                        ? DaylightTheme.Lime.primary.opacity(0.45)
                                        : DaylightTheme.accentEmerald.opacity(0.30),
                                    lineWidth: 1.5
                                )
                        )
                        .frame(
                            width: isCompact ? 42 : 48,
                            height: isCompact ? 42 : 48
                        )
                        .matchedGeometryEffect(id: "nav_sliding_indicator", in: navIndicatorNamespace)
                        .allowsHitTesting(false)
                }

                // Outer Ambient Glow
                Circle()
                    .fill(DaylightTheme.Lime.primary.opacity(colorScheme == .dark ? 0.28 : 0.20))
                    .frame(width: isCompact ? 38 : 46, height: isCompact ? 38 : 46)
                    .blur(radius: isSelected ? 6 : 3)
                    .allowsHitTesting(false)

                // Core Circular Action Button
                Circle()
                    .fill(DaylightTheme.Lime.primary)
                    .frame(width: isCompact ? 36 : 42, height: isCompact ? 36 : 42)
                    .shadow(
                        color: DaylightTheme.Lime.glow.opacity(colorScheme == .dark ? 0.5 : 0.25),
                        radius: 6,
                        x: 0,
                        y: 2
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DaylightTheme.Emerald.forest)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Daylight AI Assistant")
        .accessibilityHint("Opens on-device AI financial intelligence and voice assistance")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Color & Style Helpers

    private func itemColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? DaylightTheme.Lime.primary : DaylightTheme.accentEmerald
        } else {
            return colorScheme == .dark
                ? Color.white.opacity(0.65)
                : Color(red: 44/255, green: 79/255, blue: 63/255).opacity(0.80)
        }
    }

    private func selectSection(_ section: AppNavigationSection) {
        #if canImport(UIKit)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()
        #endif

        let springAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.78)

        // Animate the sliding indicator capsule smoothly
        withAnimation(springAnimation) {
            activeIndicatorSection = section
        }

        // Switch destination cleanly without applying spring distortion to screen contents
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedSection = section
        }
    }

    // MARK: - Glass Backdrop Fallback & Native Glass

    private var glassCapsuleBackground: some View {
        Capsule()
            .fill(
                colorScheme == .dark
                    ? Color(red: 11/255, green: 42/255, blue: 29/255).opacity(0.85)
                    : DaylightTheme.lightCream.opacity(0.90)
            )
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .frame(height: isCompact ? 48 : 60)
            .allowsHitTesting(false)
    }

    private var glassCapsuleBorder: some View {
        Capsule()
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.18)
                    : Color(red: 14/255, green: 104/255, blue: 56/255).opacity(0.16),
                lineWidth: 1
            )
            .frame(height: isCompact ? 48 : 60)
    }
}
