//
//  SiloTheme.swift
//  Silo Store
//
//  Silo design system for the app: dark is the "layers" look, light is "front"
//  (see SiloLook.swift, generated from the shared Silo tokens).
//

import CoreText
@preconcurrency import SwiftUI
@preconcurrency import UIKit

enum SiloTheme
{
    static func look(for style: UIUserInterfaceStyle) -> SiloLook
    {
        return style == .dark ? .layers : .front
    }

    static func look(for scheme: ColorScheme) -> SiloLook
    {
        return scheme == .dark ? .layers : .front
    }
}

/// Colours that follow the phone's appearance.
enum SiloColor
{
    private static func adaptive(_ look: @escaping (SiloLook) -> UIColor) -> UIColor
    {
        return UIColor { traits in look(SiloTheme.look(for: traits.userInterfaceStyle)) }
    }

    static let ground = adaptive { $0.ground }
    static let surface = adaptive { $0.surface }
    static let raised = adaptive { $0.raised }
    static let raisedStrong = adaptive { $0.raisedStrong }
    static let border = adaptive { $0.border }
    static let borderStrong = adaptive { $0.borderStrong }
    static let text = adaptive { $0.text }
    static let textMuted = adaptive { $0.textMuted }
    static let textFaint = adaptive { $0.textFaint }
    static let accent = adaptive { $0.accent }
    static let accentInk = adaptive { $0.accentInk }
    static let accentMuted = adaptive { $0.accentMuted }
    static let danger = adaptive { $0.danger }
    static let ok = adaptive { $0.ok }
    static let warn = adaptive { $0.warn }
}

extension Color
{
    static let siloGround = Color(uiColor: SiloColor.ground)
    static let siloSurface = Color(uiColor: SiloColor.surface)
    static let siloRaised = Color(uiColor: SiloColor.raised)
    static let siloRaisedStrong = Color(uiColor: SiloColor.raisedStrong)
    static let siloBorder = Color(uiColor: SiloColor.border)
    static let siloBorderStrong = Color(uiColor: SiloColor.borderStrong)
    static let siloText = Color(uiColor: SiloColor.text)
    static let siloTextMuted = Color(uiColor: SiloColor.textMuted)
    static let siloTextFaint = Color(uiColor: SiloColor.textFaint)
    static let siloAccent = Color(uiColor: SiloColor.accent)
    static let siloAccentInk = Color(uiColor: SiloColor.accentInk)
    static let siloAccentMuted = Color(uiColor: SiloColor.accentMuted)
    static let siloDanger = Color(uiColor: SiloColor.danger)
    static let siloOK = Color(uiColor: SiloColor.ok)
    static let siloWarn = Color(uiColor: SiloColor.warn)
}

/// 4 pt base, as in the shared tokens.
enum SiloSpace
{
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48

    /// Smallest tappable size.
    static let hit: CGFloat = 44
}

/// Rubik, bundled with the app (Hebrew included). Falls back to the system font if it is missing.
enum SiloFont
{
    private static let weightAxis = 2003265652 // 'wght'
    private static let baseName = "Rubik-Light"

    enum Role
    {
        case display, title, headline, body, label, caption

        var style: UIFont.TextStyle {
            switch self
            {
            case .display: return .largeTitle
            case .title: return .title2
            case .headline: return .headline
            case .body: return .body
            case .label: return .subheadline
            case .caption: return .caption1
            }
        }

        var size: CGFloat {
            switch self
            {
            case .display: return 34
            case .title: return 22
            case .headline: return 17
            case .body: return 17
            case .label: return 15
            case .caption: return 13
            }
        }

        var weight: CGFloat {
            switch self
            {
            case .display: return 800
            case .title: return 700
            case .headline: return 600
            case .body: return 400
            case .label: return 500
            case .caption: return 400
            }
        }
    }

    static func uiFont(_ role: Role) -> UIFont
    {
        return uiFont(size: role.size, weight: role.weight, style: role.style)
    }

    static func uiFont(size: CGFloat, weight: CGFloat, style: UIFont.TextStyle) -> UIFont
    {
        let font: UIFont

        if let base = UIFont(name: baseName, size: size)
        {
            let axes: [NSNumber: NSNumber] = [NSNumber(value: weightAxis): NSNumber(value: Double(weight))]
            let descriptor = base.fontDescriptor.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes
            ])
            font = UIFont(descriptor: descriptor, size: size)
        }
        else
        {
            font = UIFont.systemFont(ofSize: size, weight: systemWeight(for: weight))
        }

        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    static func font(_ role: Role) -> Font
    {
        return Font(uiFont(role) as CTFont)
    }

    private static func systemWeight(for weight: CGFloat) -> UIFont.Weight
    {
        switch weight
        {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .heavy
        }
    }
}

extension View
{
    /// Applies a Silo type role.
    func siloFont(_ role: SiloFont.Role) -> some View
    {
        return self.font(SiloFont.font(role))
    }
}

/// Global UIKit appearance, applied once at launch.
enum SiloAppearance
{
    static func apply()
    {
        let titleFont = SiloFont.uiFont(.headline)
        let largeTitleFont = SiloFont.uiFont(.display)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.titleTextAttributes = [.font: titleFont, .foregroundColor: SiloColor.text]
        navigation.largeTitleTextAttributes = [.font: largeTitleFont, .foregroundColor: SiloColor.text]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = SiloColor.accent

        let tabItem = UITabBarItemAppearance()
        let tabFont = SiloFont.uiFont(size: 11, weight: 600, style: .caption2)
        tabItem.normal.iconColor = SiloColor.textFaint
        tabItem.normal.titleTextAttributes = [.font: tabFont, .foregroundColor: SiloColor.textFaint]
        tabItem.selected.iconColor = SiloColor.accent
        tabItem.selected.titleTextAttributes = [.font: tabFont, .foregroundColor: SiloColor.accent]

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = SiloColor.ground
        tabBar.shadowColor = SiloColor.border
        tabBar.stackedLayoutAppearance = tabItem
        tabBar.inlineLayoutAppearance = tabItem
        tabBar.compactInlineLayoutAppearance = tabItem
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        UITabBar.appearance().tintColor = SiloColor.accent
    }
}
