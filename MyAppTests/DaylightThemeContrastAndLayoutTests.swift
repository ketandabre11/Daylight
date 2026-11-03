import Foundation
import SwiftUI
import Testing
import UIKit
@testable import App

@Suite("Daylight Theme — Contrast & Layout Token Tests")
struct DaylightThemeContrastAndLayoutTests {

    // MARK: - WCAG 2.1 Luminance & Contrast Formula Helper

    private func linearComponent(_ c: CGFloat) -> CGFloat {
        if c <= 0.04045 {
            return c / 12.92
        } else {
            return pow((c + 0.055) / 1.055, 2.4)
        }
    }

    private func relativeLuminance(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return 0
        }
        let rLin = linearComponent(r)
        let gLin = linearComponent(g)
        let bLin = linearComponent(b)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    private func contrastRatio(_ c1: UIColor, _ c2: UIColor) -> CGFloat {
        let l1 = relativeLuminance(of: c1)
        let l2 = relativeLuminance(of: c2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - 1. Spacing and Layout Scale Tests

    @Test("Spacing adheres strictly to 4-point scale")
    func testSpacingScale() {
        #expect(DaylightTheme.Spacing.xxs == 4)
        #expect(DaylightTheme.Spacing.xs == 8)
        #expect(DaylightTheme.Spacing.sm == 12)
        #expect(DaylightTheme.Spacing.md == 16)
        #expect(DaylightTheme.Spacing.base == 20)
        #expect(DaylightTheme.Spacing.lg == 24)
        #expect(DaylightTheme.Spacing.xl == 32)
        #expect(DaylightTheme.Spacing.xxl == 40)
    }

    @Test("Standard layout tokens match design specifications")
    func testLayoutTokens() {
        #expect(DaylightTheme.Spacing.screenMargin == 16)
        #expect(DaylightTheme.Spacing.cardPadding == 16)
        #expect(DaylightTheme.Spacing.cardGap == 16)
        #expect(DaylightTheme.Spacing.bottomNavInset == 88)
        #expect(DaylightTheme.Radius.card == 20)
    }

    // MARK: - 2. Light Theme Contrast Ratios (WCAG AA Compliance)

    @Test("Light mode: textPrimary on canvas background meets WCAG AA (>= 4.5:1)")
    func testLightTextPrimaryContrast() {
        let text = UIColor(DaylightTheme.textPrimary).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let bg = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 7.0, "textPrimary on canvas background must exceed 7.0 (actual: \(ratio))")
    }

    @Test("Light mode: textSecondary on canvas background meets WCAG AA (>= 4.5:1)")
    func testLightTextSecondaryContrast() {
        let text = UIColor(DaylightTheme.textSecondary).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let bg = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 4.5, "textSecondary on canvas background must meet WCAG AA >= 4.5 (actual: \(ratio))")
    }

    @Test("Light mode: textMuted on canvas background meets WCAG AA (>= 4.5:1)")
    func testLightTextMutedContrast() {
        let text = UIColor(DaylightTheme.textMuted).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let bg = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 4.5, "textMuted on canvas background must meet WCAG AA >= 4.5 (actual: \(ratio))")
    }

    @Test("Light mode: accentEmerald on canvas background meets WCAG AA (>= 4.5:1)")
    func testLightAccentEmeraldContrast() {
        let text = UIColor(DaylightTheme.accentEmerald).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let bg = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 4.5, "accentEmerald on canvas background must meet WCAG AA >= 4.5 (actual: \(ratio))")
    }

    @Test("Light mode: white text on accentEmerald button meets WCAG AA (>= 4.5:1)")
    func testLightButtonTextContrast() {
        let text = UIColor.white
        let bg = UIColor(DaylightTheme.accentEmerald)
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 4.5, "White text on accentEmerald must meet WCAG AA >= 4.5 (actual: \(ratio))")
    }

    @Test("Dark mode: forest green text on lime button meets WCAG AAA (>= 7.0:1)")
    func testDarkButtonTextContrast() {
        let text = UIColor(DaylightTheme.Emerald.forest)
        let bg = UIColor(DaylightTheme.accentLime)
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 7.0, "Forest text on accentLime must meet WCAG AAA >= 7.0 (actual: \(ratio))")
    }

    @Test("Dark mode: textPrimary on dark background meets WCAG AAA (>= 7.0:1)")
    func testDarkTextPrimaryContrast() {
        let text = UIColor(DaylightTheme.textPrimary).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let bg = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let ratio = contrastRatio(text, bg)
        #expect(ratio >= 7.0, "textPrimary in dark mode must exceed 7.0 (actual: \(ratio))")
    }

    // MARK: - 3. Live Appearance Resolution

    @Test("Semantic tokens correctly differentiate between light and dark traits")
    func testAppearanceDifferentiation() {
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)

        let primaryLight = UIColor(DaylightTheme.textPrimary).resolvedColor(with: lightTrait)
        let primaryDark = UIColor(DaylightTheme.textPrimary).resolvedColor(with: darkTrait)
        #expect(primaryLight != primaryDark, "textPrimary should have distinct values for light vs dark mode")

        let canvasLight = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: lightTrait)
        let canvasDark = UIColor(DaylightTheme.canvasBackground).resolvedColor(with: darkTrait)
        #expect(canvasLight != canvasDark, "canvasBackground should have distinct values for light vs dark mode")
    }
}

