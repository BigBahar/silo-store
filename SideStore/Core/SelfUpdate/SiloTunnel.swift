//
//  SiloTunnel.swift
//  Silo Store
//

import Foundation

/// Which tunnel carries the app's connection to its own device.
///
/// - LocalDevVPN: the on-device loopback VPN (the default).
/// - Tailscale: the phone reaches a relay on the tailnet that bounces its own traffic back
///   (Connection Config "remote endpoint" with the relay's Tailscale address). Tailscale is
///   switched on and off by two Shortcuts the user makes with Tailscale's Connect and
///   Disconnect actions.
enum SiloTunnel
{
    enum Mode: String
    {
        case localDevVPN
        case tailscale
    }
    
    private static let modeKey = "siloTunnelMode"
    private static let onShortcutKey = "siloTunnelOnShortcut"
    private static let offShortcutKey = "siloTunnelOffShortcut"
    
    static let defaultOnShortcut = "Silo Tunnel On"
    static let defaultOffShortcut = "Silo Tunnel Off"
    
    static var mode: Mode {
        get { return Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .localDevVPN }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            self.applyMode()
        }
    }
    
    static var onShortcutName: String {
        get { return UserDefaults.standard.string(forKey: onShortcutKey) ?? defaultOnShortcut }
        set { UserDefaults.standard.set(newValue, forKey: onShortcutKey) }
    }
    
    static var offShortcutName: String {
        get { return UserDefaults.standard.string(forKey: offShortcutKey) ?? defaultOffShortcut }
        set { UserDefaults.standard.set(newValue, forKey: offShortcutKey) }
    }
    
    /// The name to show for the tunnel that is switched.
    static var displayName: String {
        return self.mode == .tailscale ? "Tailscale" : "LocalDevVPN"
    }
    
    /// In Tailscale mode the device is reached through the relay, so the local VPN path is off.
    static func applyMode()
    {
        ConnectionConfig.shared.useLocalVPN = (self.mode == .localDevVPN)
    }
    
    /// Runs a Shortcut and returns to Silo Store when it finishes.
    static func shortcutURL(name: String) -> URL?
    {
        var components = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "silostore://")
        ]
        return components?.url
    }
}
